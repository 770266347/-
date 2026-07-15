#!/usr/bin/env python3
import argparse
import base64
import json
import mimetypes
import os
import sys
import time
import uuid
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")


DEFAULT_BASE_URL = "https://aicode-api2.gz4399.com/api/v1"
DEFAULT_TIMEOUT = 650


def read_api_key(args):
    if args.api_key:
        return args.api_key

    for name in ("GPT_IMAGE2_API_KEY", "AICODE_API_KEY", "OPENAI_API_KEY"):
        value = os.environ.get(name)
        if value:
            return value

    raise SystemExit(
        "Missing API key. Set GPT_IMAGE2_API_KEY/AICODE_API_KEY/OPENAI_API_KEY "
        "or pass --api-key cr_xxxxxxxx."
    )


def endpoint(base_url, path):
    return base_url.rstrip("/") + path


def request_headers(api_key, session_id=None, content_type="application/json"):
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": content_type,
    }
    if session_id:
        headers["x-session-id"] = session_id
    return headers


def request_json(base_url, path, api_key, payload, session_id=None, timeout=DEFAULT_TIMEOUT):
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    req = Request(
        endpoint(base_url, path),
        data=body,
        headers=request_headers(api_key, session_id),
        method="POST",
    )
    return decode_response(req, timeout)


def decode_response(req, timeout):
    try:
        with urlopen(req, timeout=timeout) as resp:
            data = resp.read()
    except HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise SystemExit(f"HTTP {exc.code}: {detail}") from exc
    except URLError as exc:
        raise SystemExit(f"Request failed: {exc}") from exc

    try:
        return json.loads(data.decode("utf-8"))
    except json.JSONDecodeError as exc:
        raise SystemExit(f"Response is not JSON: {data[:300]!r}") from exc


def save_b64_image(b64_value, output_path):
    output_path = Path(output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(base64.b64decode(b64_value))
    return output_path


def numbered_output(output_path, index, total):
    output_path = Path(output_path)
    if total == 1:
        return output_path
    return output_path.with_name(f"{output_path.stem}_{index + 1}{output_path.suffix}")


def save_images_api_response(resp, output_path):
    items = resp.get("data") or []
    if not items:
        raise SystemExit(f"No image data in response: {json.dumps(resp, ensure_ascii=False)[:500]}")

    saved = []
    for index, item in enumerate(items):
        b64_value = item.get("b64_json") or item.get("b64")
        if not b64_value:
            raise SystemExit(f"Missing b64_json in item {index}: {item}")
        saved.append(save_b64_image(b64_value, numbered_output(output_path, index, len(items))))
    return saved


def save_responses_api_response(resp, output_path):
    outputs = resp.get("output") or []
    images = [
        item.get("result")
        for item in outputs
        if item.get("type") == "image_generation_call" and item.get("result")
    ]
    if not images:
        raise SystemExit(f"No image_generation_call result in response: {json.dumps(resp, ensure_ascii=False)[:800]}")

    saved = []
    for index, b64_value in enumerate(images):
        saved.append(save_b64_image(b64_value, numbered_output(output_path, index, len(images))))
    return saved


def image_data_url(path):
    path = Path(path)
    mime = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
    if mime not in {"image/png", "image/jpeg", "image/webp"}:
        raise SystemExit(f"Unsupported image mime for {path}: {mime}. Use PNG, JPEG, or WEBP.")
    b64_value = base64.b64encode(path.read_bytes()).decode("ascii")
    return f"data:{mime};base64,{b64_value}"


def multipart_body(fields, files):
    boundary = "----gpt-image2-" + uuid.uuid4().hex
    chunks = []

    for name, value in fields:
        chunks.extend(
            [
                f"--{boundary}\r\n".encode("utf-8"),
                f'Content-Disposition: form-data; name="{name}"\r\n\r\n'.encode("utf-8"),
                str(value).encode("utf-8"),
                b"\r\n",
            ]
        )

    for name, path in files:
        path = Path(path)
        mime = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
        if mime not in {"image/png", "image/jpeg", "image/webp"}:
            raise SystemExit(f"Unsupported image mime for {path}: {mime}. Use PNG, JPEG, or WEBP.")
        chunks.extend(
            [
                f"--{boundary}\r\n".encode("utf-8"),
                (
                    f'Content-Disposition: form-data; name="{name}"; '
                    f'filename="{path.name}"\r\n'
                ).encode("utf-8"),
                f"Content-Type: {mime}\r\n\r\n".encode("utf-8"),
                path.read_bytes(),
                b"\r\n",
            ]
        )

    chunks.append(f"--{boundary}--\r\n".encode("utf-8"))
    return boundary, b"".join(chunks)


def request_multipart(base_url, path, api_key, fields, files, session_id=None, timeout=DEFAULT_TIMEOUT):
    boundary, body = multipart_body(fields, files)
    headers = request_headers(
        api_key,
        session_id,
        content_type=f"multipart/form-data; boundary={boundary}",
    )
    req = Request(endpoint(base_url, path), data=body, headers=headers, method="POST")
    return decode_response(req, timeout)


def cmd_generate(args):
    payload = {
        "model": args.model,
        "prompt": args.prompt,
        "n": args.n,
        "size": args.size,
        "quality": args.quality,
        "output_format": args.output_format,
        "response_format": "b64_json",
    }
    if args.dry_run:
        print(json.dumps(payload, ensure_ascii=False, indent=2))
        return

    resp = request_json(
        args.base_url,
        "/images/generations",
        read_api_key(args),
        payload,
        args.session_id,
        args.timeout,
    )
    print_saved(save_images_api_response(resp, args.output))


def cmd_edit(args):
    fields = [
        ("model", args.model),
        ("prompt", args.prompt),
        ("n", args.n),
        ("size", args.size),
        ("quality", args.quality),
        ("output_format", args.output_format),
        ("response_format", "b64_json"),
    ]
    files = [("image[]" if len(args.image) > 1 else "image", image) for image in args.image]

    if args.dry_run:
        print(json.dumps({"fields": fields, "files": files}, ensure_ascii=False, indent=2))
        return

    resp = request_multipart(
        args.base_url,
        "/images/edits",
        read_api_key(args),
        fields,
        files,
        args.session_id,
        args.timeout,
    )
    print_saved(save_images_api_response(resp, args.output))


def cmd_response_generate(args):
    payload = {
        "model": args.driver_model,
        "input": args.prompt,
        "store": False,
        "tools": [
            {
                "type": "image_generation",
                "model": args.model,
                "action": "generate",
                "size": args.size,
                "quality": args.quality,
                "output_format": args.output_format,
            }
        ],
    }
    if args.dry_run:
        print(json.dumps(payload, ensure_ascii=False, indent=2))
        return

    resp = request_json(
        args.base_url,
        "/responses",
        read_api_key(args),
        payload,
        args.session_id,
        args.timeout,
    )
    print_saved(save_responses_api_response(resp, args.output))


def cmd_response_edit(args):
    content = [{"type": "input_text", "text": args.prompt}]
    content.extend({"type": "input_image", "image_url": image_data_url(path)} for path in args.image)
    payload = {
        "model": args.driver_model,
        "input": [{"role": "user", "content": content}],
        "store": False,
        "tools": [
            {
                "type": "image_generation",
                "model": args.model,
                "action": "edit",
                "size": args.size,
                "quality": args.quality,
                "output_format": args.output_format,
            }
        ],
    }
    if args.dry_run:
        preview = dict(payload)
        preview["input"] = "[input_text + input_image data URLs omitted]"
        print(json.dumps(preview, ensure_ascii=False, indent=2))
        return

    resp = request_json(
        args.base_url,
        "/responses",
        read_api_key(args),
        payload,
        args.session_id,
        args.timeout,
    )
    print_saved(save_responses_api_response(resp, args.output))


def print_saved(paths):
    for path in paths:
        print(f"saved: {path}")


def add_common(parser):
    parser.add_argument("--api-key", help="API key, e.g. cr_xxxxxxxx. Prefer env GPT_IMAGE2_API_KEY.")
    parser.add_argument("--base-url", default=DEFAULT_BASE_URL, help=f"Default: {DEFAULT_BASE_URL}")
    parser.add_argument("--model", default="gpt-image-2")
    parser.add_argument("--session-id", help="Sticky session id, sent as x-session-id.")
    parser.add_argument("--timeout", type=int, default=DEFAULT_TIMEOUT)
    parser.add_argument("--dry-run", action="store_true", help="Print request payload without sending it.")


def add_image_options(parser, allow_n=True):
    parser.add_argument("-p", "--prompt", required=True)
    parser.add_argument("-o", "--output", default=f"image_{int(time.time())}.png")
    parser.add_argument("--size", default="1024x1024")
    parser.add_argument("--quality", default="low", choices=("low", "medium", "high", "auto", "standard", "hd"))
    parser.add_argument("--output-format", default="png", choices=("png", "jpeg", "webp"))
    if allow_n:
        parser.add_argument("-n", type=int, default=1)


def build_parser():
    parser = argparse.ArgumentParser(
        description="Client for the 4399 GPT-IMAGE-2 image generation API."
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    generate = subparsers.add_parser("generate", help="Text-to-image via /images/generations.")
    add_common(generate)
    add_image_options(generate)
    generate.set_defaults(func=cmd_generate)

    edit = subparsers.add_parser("edit", help="Image edit/reference image via multipart /images/edits.")
    add_common(edit)
    add_image_options(edit)
    edit.add_argument("--image", required=True, action="append", help="Input image path. Repeat for multiple images.")
    edit.set_defaults(func=cmd_edit)

    response_generate = subparsers.add_parser("response-generate", help="Text-to-image via /responses.")
    add_common(response_generate)
    add_image_options(response_generate, allow_n=False)
    response_generate.add_argument("--driver-model", default="gpt-5.4")
    response_generate.set_defaults(func=cmd_response_generate)

    response_edit = subparsers.add_parser("response-edit", help="Image edit/reference image via /responses input_image.")
    add_common(response_edit)
    add_image_options(response_edit, allow_n=False)
    response_edit.add_argument("--driver-model", default="gpt-5.4")
    response_edit.add_argument("--image", required=True, action="append", help="Input image path. Repeat for multiple images.")
    response_edit.set_defaults(func=cmd_response_edit)

    return parser


def main(argv=None):
    parser = build_parser()
    args = parser.parse_args(argv)
    args.func(args)


if __name__ == "__main__":
    main()
