# Staging-only failed 00051 disposition

The isolated staging project `qvuidmgddjoircheapzk` applied the experimental
`00051_restore_legacy_billing_compatibility.sql` during emergency acceptance.
Its SHA-256 was:

`DF791EF693861AC357A9C894F4178CD04795687865ECADC20BFD52282304BD58`

It restored authenticated execution of the obsolete five-argument billing RPC.
Runtime acceptance rejected it because an inactive user retaining a direct
permission and a crafted Draft test could both reach legacy billing.

Production project `rncjxstujioagcezvfkb` never applied that experiment and
remains at `00050`. The failed SQL is retained under `docs/staging-only/` as
incident evidence and is excluded from the production migration set.

The legitimate production successor is
`00051_inactive_user_permission_enforcement.sql`. Before applying that file to
isolated staging, explicitly mark only staging migration version `00051` as
reverted, verify staging head becomes `00050`, and then apply the legitimate
`00051`. This ledger reconciliation is staging-only, deliberate, and must be
recorded in acceptance evidence. Never repair or rewrite production history.
