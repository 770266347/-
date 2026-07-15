# GPT-IMAGE-2 接口使用说明

已接入 PDF 中的 4399 GPT-IMAGE-2 接口，脚本为 `gpt_image2_client.py`。

## 1. 配置 API Key

PowerShell：

```powershell
$env:GPT_IMAGE2_API_KEY="cr_xxxxxxxx"
```

脚本也会读取 `AICODE_API_KEY` 或 `OPENAI_API_KEY`。当前已验证可用的默认 Base URL：

```text
https://aicode-api2.gz4399.com/api/v1
```

如需切换到文档里的其他域名，可加：

```powershell
--base-url "https://aicode-api.gz4399.com/api/v1"
```

## 2. 文生图

对应 PDF 的 `POST /api/v1/images/generations`：

```powershell
py -3 gpt_image2_client.py generate `
  -p "一只橘色柴犬贴纸，纯色背景" `
  -o output.png `
  --size 1024x1024 `
  --quality low
```

一次出多张：

```powershell
py -3 gpt_image2_client.py generate -p "洛克王国风格宠物头像" -n 3 -o output.png
```

输出会保存为 `output_1.png`、`output_2.png`、`output_3.png`。

## 3. 图生图 / 参考图编辑

对应 PDF 的 `POST /api/v1/images/edits`：

```powershell
py -3 gpt_image2_client.py edit `
  --image input.png `
  -p "保留主体，背景换成深蓝渐变星空" `
  -o edited.png `
  --size 1024x1024 `
  --quality low
```

多图参考：

```powershell
py -3 gpt_image2_client.py edit `
  --image subject.png `
  --image reference.png `
  -p "参考第一张主体颜色与第二张氛围光，融合成赛博朋克场景" `
  -o merged.png
```

## 4. Responses 方式

文生图：

```powershell
py -3 gpt_image2_client.py response-generate `
  -p "极简橘色柴犬贴纸，纯色背景" `
  -o response-image.png
```

图生图：

```powershell
py -3 gpt_image2_client.py response-edit `
  --image input.png `
  -p "参考这张图，把它改成赛博朋克蓝紫色霓虹风格" `
  -o response-edited.png
```

## 5. 调试

不发请求，只看请求体：

```powershell
py -3 gpt_image2_client.py generate -p "测试 prompt" --dry-run
```

同一个用户多次请求想固定上游账号时，加：

```powershell
--session-id "user-001"
```

注意：PDF 说明 `background=transparent`、`mask`、`512x512` 等参数不建议使用或不支持，脚本没有默认发送这些字段。
