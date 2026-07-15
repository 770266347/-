# image2 接口迁移包

这个目录包含 GPT-IMAGE-2 接口接入所需文件：

- `gpt_image2_client.py`：可直接调用的 Python 客户端
- `GPT_IMAGE2_USAGE.md`：命令使用说明
- `Codex+GPT-IMAGE-2+图像生成接口文档-4399百科.pdf`：原始接口文档
- `api_test_output_api2.png`：已验证成功的测试输出
- `.env.example`：API Key 环境变量示例，不包含真实 key

默认 Base URL 已切到验证成功的：

```text
https://aicode-api2.gz4399.com/api/v1
```

PowerShell 临时配置 key：

```powershell
$env:GPT_IMAGE2_API_KEY="cr_xxxxxxxx"
```

文生图：

```powershell
py -3 gpt_image2_client.py generate -p "一只橘色柴犬贴纸，纯色背景" -o output.png
```

图生图：

```powershell
py -3 gpt_image2_client.py edit --image input.png -p "保留主体，背景换成深蓝渐变星空" -o edited.png
```
