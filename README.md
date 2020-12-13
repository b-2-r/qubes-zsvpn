# qubes-zsvpn

Use ZSVPN through a ProxyVM running on Qubes OS.

## How it works

The script first creates and starts a *temporary* AppVM. This AppVM is used to download and start zSec's [VPN client](https://zsvpn.com/downloads). It then waits for the user to log in and connect to their preferred VPN server. Once a connection is established, it parses OpenVPN's command line arguments, this includes the VPN server's connection information, as well as the path to OpenVPN's client-side config file and the paths to the VPN credentials downloaded by the VPN client (e.g. ca.crt).

After getting all these information from the VPN client, the script proceeds with transferring the aforementioned files to dom0. Once they are placed in dom0, it modifies OpenVPN's config file in a way that it fulfills [Qubes-vpn-support](https://github.com/tasket/Qubes-vpn-support)'s setup requirements.

The script then creates the actual ProxyVM. This ProxyVM is used to download and install Qubes-vpn-support. After Qubes-vpn-support was downloaded and installed, the script transfers all files from dom0 to the ProxyVM. As a final step the ProxyVM is restarted.

## How-To Guide

Clone this repository.

```
[user@domain ~] git clone https://github.com/b-2-r/qubes-zsvpn.git
```

Start a dom0 console.

1. Click on the **Applications** icon on the top left corner of you screen.

2. Click on **Terminal Emulator**

Copy the *create-proxyvm.sh* script to dom0.

```
[user@dom0 ~] qvm-run --pass-io domain "cat /home/user/qubes-zsvpn/create-proxyvm.sh" > create-proxyvm.sh
```

Give the script execute permission.

```
[user@dom0 ~] chmod +x create-proxyvm.sh
```

Invoke the script.

```
[user@dom0 ~] ./create-proxyvm.sh
[INFO] Creating and starting temporary AppVM (zsvpn-client).
[INFO] Downloading, verifying, and unpacking zsvpn_2.1.8.zip...
[INFO] ...this may take some time depending on your internet connection.
[INFO] Starting VPN client (zsvpn).
Press any key to continue...
```

At this point *create-proxyvm.sh* starts the VPN client. Wait until the client did finish launching. Then, log into the VPN client and establish a connection with your preferred VPN server.  If the client shows you a **"YOU ARE CONNECTED"** message, go back to your dom0 console and wake up the script by pressing any key on your keyboard.

> **Note:**
> You must wait until you see the **"YOU ARE CONNECTED"** message from the VPN client before you proceed with the script.
> 
> **Also note:**
> If the client shows you a **"Problem checking IP Location Error: ETIMEDOUT"** message, you can safely ignore this, it will not influence the final ProxyVM in any way.

If everything is working fine you should see a few more messages.

```
[INFO] Parsing OpenVPN's command line arguments.
[INFO] Transfering OpenVPN files to dom0.
[INFO] Modifying vpn-client.conf.
[INFO] Shutting down and removing zsvpn-client.
[INFO] Creating and starting ProxyVM (sys-zsvpn).
[INFO] Downloading and installing Qubes-vpn-support.
[INFO] Transfering OpenVPN files to sys-zsvpn.
[INFO] Restarting sys-zsvpn.
[INFO] Done, you should soon see a 'LINK IS UP' pupup notification.
[INFO] Have fun with your new sys-zsvpn ProxyVM :)
```

Congrats, your ProxyVM (*sys-zsvpn*) is ready to use. To connect any AppVM with your *sys-zsvp*n ProxyVM you need to go through the following steps.

1. Open the **Qubes Settings** of the AppVM you wish to connect.

2. In the Basic tab, change **Networking** to *sys-zsvpn*.

3. Click on **OK**.

You can check your VPN setup by visiting [https://ipleak.net](https://ipleak.net). 

## Testing Environment

* Qubes release 4.0 (R4.0)

* Fedora release 32 (Thirty Two)

* Debian 10.7
