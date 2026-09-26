## How VPN providers are managed

The upstream project used to bundle configuration files for many VPN providers. As the number of providers and configurations grew, upstream moved static `.ovpn` files to
[haugene/vpn-configs-contrib](https://github.com/haugene/vpn-configs-contrib).

The container fetches those files at startup. Provider scripts that fetch configurations dynamically remain in this repository. This gives the container two provider types: `internal` and `external`.

For external providers, you can use a fork of the configuration repository as the source for startup downloads.

## Out-of-the-box supported providers

If you can't find your provider you are welcome to head over to the 
[config repo](https://github.com/haugene/vpn-configs-contrib) to request it or add it yourself.
Keep in mind that some providers generate configs per user where the authentication details are a part
of the config and they can therefore not be added here but has to be manually supplied by the user.
You can use any OpenVPN config with this container by mounting it as a file in the container.
For more info on that see the [using a custom provider](#using_a_custom_provider) section.

### Internal Providers

These providers are implemented as a script in this project and will automatically
download new configs directly from the provider on container startup.

| Provider Name             | Config Value (`OPENVPN_PROVIDER`) |
| :------------------------ | :-------------------------------- |
| IPVanish                  | `IPVANISH`                        |
| NordVPN                   | `NORDVPN`                         |
| Private Internet Access   | `PIA`                             |
| VyprVpn                   | `VYPRVPN`                         |

### External Providers

These providers are fetched from the upstream [config repo](https://github.com/haugene/vpn-configs-contrib) on startup.
Their configurations must be updated there when a provider changes them.

The files and folders in that repository are the most current list of external providers and configurations.


| Provider Name             | Config Value (`OPENVPN_PROVIDER`) |
| :------------------------ | :-------------------------------- |
| Anonine                   | `ANONINE`                         |
| AnonVPN                   | `ANONVPN`                         |
| BlackVPN                  | `BLACKVPN`                        |
| BTGuard                   | `BTGUARD`                         |
| Cryptostorm               | `CRYPTOSTORM`                     |
| ExpressVPN                | `EXPRESSVPN`                      |
| FastestVPN                | `FASTESTVPN`                      |
| FreeVPN                   | `FREEVPN`                         |
| FrootVPN                  | `FROOT`                           |
| FrostVPN                  | `FROSTVPN`                        |
| Getflix                   | `GETFLIX`                         |
| GhostPath                 | `GHOSTPATH`                       |
| Giganews                  | `GIGANEWS`                        |
| HideMe                    | `HIDEME`                          |
| HideMyAss                 | `HIDEMYASS`                       |
| IntegrityVPN              | `INTEGRITYVPN`                    |
| IronSocket                | `IRONSOCKET`                      |
| Ivacy                     | `IVACY`                           |
| IVPN                      | `IVPN`                            |
| OctaneVPN                 | `OCTANEVPN`                       |
| OVPN                      | `OVPN`                            |
| Privado                   | `PRIVADO`                         |
| PrivateVPN                | `PRIVATEVPN`                      |
| ProtonVPN                 | `PROTONVPN`                       |
| proXPN                    | `PROXPN`                          |
| PureVPN                   | `PUREVPN`                         |
| RA4W VPN                  | `RA4W`                            |
| SaferVPN                  | `SAFERVPN`                        |
| SlickVPN                  | `SLICKVPN`                        |
| SlickVPNCore              | `SLICKVPNCORE`                    |
| Smart DNS Proxy           | `SMARTDNSPROXY`                   |
| SmartVPN                  | `SMARTVPN`                        |
| Surfshark                 | `SURFSHARK`                       |
| TigerVPN                  | `TIGER`                           |
| TorGuard                  | `TORGUARD`                        |
| Trust.Zone                | `TRUSTZONE`                       |
| TunnelBear                | `TUNNELBEAR`                      |
| VPN.AC                    | `VPNAC`                           |
| VPNArea.com               | `VPNAREA`                         |
| VPNBook.com               | `VPNBOOK`                         |
| VPNFacile                 | `VPNFACILE`                       |
| VPN.ht                    | `VPNHT`                           |
| VPNTunnel                 | `VPNTUNNEL`                       |
| VPNUnlimited              | `VPNUNLIMITED`                    |
| Windscribe                | `WINDSCRIBE`                      |
| ZoogVPN                   | `ZOOGVPN`                         |

## Use your own config without building the image

If you have a .ovpn file from your VPN provider and you want to use it but you either don't
know how to build the image yourself or if you don't want to there is another way.

Check out the [guide for this](https://github.com/haugene/vpn-configs-contrib/blob/main/CONTRIBUTING.md)
in the config repo.

## Using a local single .ovpn file from a provider
For some providers, like AirVPN, the .ovpn files are generated per user and contain credentials. 
These files can not be hosted anywhere publicly visible. Then you can mount the files into the container
and use them directly from your local host.

**Grab all files from your provider** (usually a .zip file to download & unzip)

**Copy them into a folder on your Docker host**, there might be .ovpn files and ca.cert as well (example below /volume1/docker/ipvanish/)

**Mount the volume**
Compose sample:
```
             - /volume1/docker/ipvanish/:/etc/openvpn/custom/
```
**Declare the Custom provider, the target server and login/password**
Also important to note here is that `OPENVPN_CONFIG` value needs to be the name of the ovpn file wanting to be referenced in the `/etc/openvpn/custom` volume. In the example below the ovpn file name is `ipvanish-UK-Maidenhead-lhr-c02.ovpn` 

Compose sample:
```
            - OPENVPN_PROVIDER=custom
            - OPENVPN_CONFIG=ipvanish-UK-Maidenhead-lhr-c02
            - OPENVPN_USERNAME=user
            - OPENVPN_PASSWORD=pass
```
Docker ENV vars sample: 
```
              -e OPENVPN_PROVIDER=custom \
              -e OPENVPN_CONFIG=ipvanish-UK-Maidenhead-lhr-c02 \
              -e OPENVPN_USERNAME=user \
              -e OPENVPN_PASSWORD=pass \
```

### Do not mount single config file

Do not mount a single config directly. The container will fail if you try, since it causes sed errors when modify-openvpn-config.sh is executed.
Instead mount the directory where the config exists.

```bash
sed: cannot rename /etc/openvpn/custom/sedHeF3gS: Device or resource busy
```

## Using custom OpenVPN config bundle for supported providers

Many of the VPN provider integrations download a ZIP bundle of the OpenVPN configs from the provider when the container starts. You may want to provide your own config bundle ZIP as opposed to having the container download it. This may be useful if the download URL for the config bundle is blocked on your network.

Currently, this is only supported for Private Internet Access. You can enable this by setting the appropriate env variable (PIA_CUSTOM_BUNDLE) to the location of the zip on the container, and then you must mount the file into the Docker container.

Docker ENV vars sample:
```
              -v /localMachine/pia-config.zip:/etc/openvpn/pia_custom_bundle.zip:ro \
              -e PIA_CUSTOM_BUNDLE=/etc/openvpn/pia_custom_bundle.zip \
```

Compose sample:
```
              environment:
                - OPENVPN_PROVIDER=pia
                - PIA_CUSTOM_BUNDLE=/etc/openvpn/pia_custom_bundle.zip
              volumes:
                - /localMachine/pia-config.zip:/etc/openvpn/pia_custom_bundle.zip:ro
```

To be clear, the ZIP should contain all the PIA OVPN files at the top-level. For example, if you set OPENVPN_CONFIG to uk_london, uk_london.ovpn should exist in the zip.
