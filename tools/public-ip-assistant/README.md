# Bimal Pathology Public IP Assistant

This is a separate operator utility. It does not reference the SMS Gateway,
Supabase, Sparrow credentials, or any clinical application component.

At launch it registers the current executable under the current user's
`HKCU\Software\Microsoft\Windows\CurrentVersion\Run` key. On each login it:

1. queries `api.ipify.org` with two bounded attempts;
2. falls back to `ipv4.icanhazip.com` with two bounded attempts;
3. validates a public IPv4 address;
4. exits silently if it matches the last confirmed address;
5. otherwise presents Copy IP, Open Sparrow Panel, Confirm Updated, and Later.

Only Confirm Updated changes the last confirmed address. A detection failure or
invalid response never overwrites the existing state.

State is stored at:

`%LOCALAPPDATA%\BimalPathology\PublicIpAssistant\state.json`

It contains only `last_confirmed_public_ip`, `detected_public_ip`, `detected_at`,
and `confirmed_at`. Uninstall removes startup registration but intentionally
leaves this small operator-confirmed state for safe reinstall continuity.
