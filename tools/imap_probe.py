#!/usr/bin/env python3
"""试连邮箱：只读，不发信、不改任何邮件。

用法：
    python3 tools/imap_probe.py <IMAP服务器> <端口> <邮箱地址>
例：
    python3 tools/imap_probe.py imap.example.com 993 me@example.com

密码运行时在终端里输入（不显示、不保存）。
做三件事：
  1. 登录
  2. 列出所有文件夹（找出「已发送」叫什么名字，以后发信要存进去）
  3. 列出收件箱最近 5 封信的发件人、日期、标题
"""
import email
import email.header
import getpass
import imaplib
import ssl
import sys


def decode(value):
    if not value:
        return ""
    parts = []
    for text, charset in email.header.decode_header(value):
        if isinstance(text, bytes):
            text = text.decode(charset or "utf-8", errors="replace")
        parts.append(text)
    return "".join(parts)


def decode_folder_name(raw):
    # IMAP 文件夹名用 modified UTF-7 编码，中文名会是 &xxx- 这种样子
    import base64
    out, i = [], 0
    while i < len(raw):
        if raw[i] == "&":
            j = raw.index("-", i)
            if j == i + 1:
                out.append("&")
            else:
                b64 = raw[i + 1:j].replace(",", "/")
                b64 += "=" * (-len(b64) % 4)
                out.append(base64.b64decode(b64).decode("utf-16-be"))
            i = j + 1
        else:
            out.append(raw[i])
            i += 1
    return "".join(out)


def main():
    if len(sys.argv) != 4:
        print(__doc__)
        sys.exit(1)
    host, port, user = sys.argv[1], int(sys.argv[2]), sys.argv[3]
    password = getpass.getpass(f"请输入 {user} 的客户端密码（输入时不显示）：")

    print(f"\n[1/3] 连接 {host}:{port} …")
    conn = imaplib.IMAP4_SSL(host, port, ssl_context=ssl.create_default_context())
    try:
        conn.login(user, password)
    except imaplib.IMAP4.error as e:
        print(f"  ✗ 登录失败：{e}")
        sys.exit(2)
    print("  ✓ 登录成功")

    # 有些国内邮箱要求客户端报上身份才放行（RFC 2971 ID 命令），失败无所谓
    try:
        imaplib.Commands["ID"] = ("AUTH", "SELECTED")
        conn._simple_command("ID", '("name" "AutoTransMail" "version" "0.1")')
    except Exception:
        pass

    print("\n[2/3] 文件夹列表：")
    typ, folders = conn.list()
    for line in folders or []:
        s = line.decode(errors="replace")
        name = s.rsplit(' "/" ', 1)[-1].strip('"') if ' "/" ' in s else s
        flags = s.split(")")[0] + ")"
        print(f"  - {decode_folder_name(name)}    {flags}")

    print("\n[3/3] 收件箱最近 5 封：")
    typ, data = conn.select("INBOX", readonly=True)
    total = int(data[0])
    print(f"  收件箱共 {total} 封")
    for num in range(total, max(total - 5, 0), -1):
        typ, msg_data = conn.fetch(str(num), "(BODY.PEEK[HEADER.FIELDS (FROM DATE SUBJECT)])")
        msg = email.message_from_bytes(msg_data[0][1])
        print(f"  • {decode(msg['Date'])}")
        print(f"    发件人：{decode(msg['From'])}")
        print(f"    标题：  {decode(msg['Subject'])}")

    conn.logout()
    print("\n全部完成：飞书邮箱可以用 IMAP 收信。")


if __name__ == "__main__":
    main()
