# Retired Cloud SMS dispatcher

This directory is a fail-closed tombstone. It has no Sparrow endpoint, secret,
queue binding, consumer, or schedule. Do not deploy it as an SMS sender.

The only supported production path is:

`LIS -> Supabase sms_queue_items -> BimalPathologySMSGateway (Windows) -> Sparrow`
