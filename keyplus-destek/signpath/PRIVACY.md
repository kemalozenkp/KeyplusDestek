# Keyplus Destek — privacy disclosure draft

**Draft for technical and company review; not a published privacy notice.**

Operator/contact: Keyplus Yazılım Donanım Danışmanlık Ltd Şti,
info@keyplus.com.tr.

Keyplus Destek is a Windows remote support client. It does not use a Keyplus
ERP account or ERP database. The currently published configuration selects
the Keyplus-operated rendezvous/relay endpoint `31.210.154.245`, using TCP
21115/21116/21117 and UDP 21116. The server address and public key are included
in the downloadable `data/keyplus-server.json` configuration. The public key
is not a password or private signing key.

The application uses a device ID and connection metadata to establish remote
sessions. A permitted remote session can transmit screen content, remote
keyboard/mouse input, clipboard data and transferred files according to the
enabled session permissions. Direct connectivity is attempted; relay service
can carry session traffic when required. This draft does not claim that the
operator has completed an independent encryption or server-data audit.

Quick Support is the initial mode and requests user acceptance. A device
owner can configure unattended access using a device-specific password and
Windows service. This allows subsequent authorized connections without a
fresh acceptance click. The application has no shared permanent password.
The owner can change security settings or uninstall the service/application.

Device configuration and diagnostic logs are stored locally under the
application's Windows profiles. Diagnostic files can contain connection IDs,
addresses and error details; review them before sharing. Passwords or customer
session data must not be included in a signing application or public source.

Before publication, the operator must confirm server-side logging, retention,
deletion/contact procedures and any applicable company privacy statements.
The disclosure must be presented to users at the appropriate installation or
connection step. These items are pending; this draft is not evidence that
they have been implemented or legally reviewed.
