# Amethyst

[![Stable Images](https://github.com/iarsslen/amethyst/actions/workflows/build-image-stable.yml/badge.svg)](https://github.com/iarsslen/amethyst/actions/workflows/build-image-stable.yml)[![Latest Images](https://github.com/iarsslen/amethyst/actions/workflows/build-image-latest-main.yml/badge.svg)](https://github.com/iarsslen/amethyst/actions/workflows/build-image-latest-main.yml)

**Amethyst** is a cloud-native desktop operating system built on Fedora, using container technology and atomic updates.

For end users, it aims to be as reliable as a Chromebook with near-zero maintenance. For developers, it offers a cloud-native workflow with integrated container tools, declarative system management and CI/CD-built images.

Amethyst is created and maintained by **Arsslen Idadi** ([@iarsslen](https://github.com/iarsslen)).

## Mission

Amethyst aims to be a robust, cloud-native desktop that brings enterprise-grade infrastructure practices to everyday computing:

- **Reliability**: Atomic updates keep the system stable
- **Developer Experience**: Integrated cloud-native tooling and workflows, including Kubernetes and container support
- **Sustainability**: Low maintenance overhead through modern cloud-native build infrastructure

## Images

| Image | Description |
| --- | --- |
| `ghcr.io/iarsslen/amethyst` | The standard desktop |
| `ghcr.io/iarsslen/amethyst-dx` | Developer Experience: adds Docker, Incus, libvirt and developer tools |
| `ghcr.io/iarsslen/amethyst-nvidia-open` | Standard desktop with the open NVIDIA kernel modules |
| `ghcr.io/iarsslen/amethyst-dx-nvidia-open` | Developer Experience with the open NVIDIA kernel modules |

Each image is published in the `stable`, `latest` and `beta` streams.

## Getting Started

From an existing Fedora Atomic or Universal Blue system, switch to Amethyst with:

```bash
sudo bootc switch ghcr.io/iarsslen/amethyst:stable
```

Then reboot. Replace `amethyst` with any image name from the table above, and `stable` with the stream you want.

### Building locally

```bash
just build amethyst latest main
just build amethyst-dx latest main
```

### Secure Boot

Secure Boot is supported. Amethyst uses the kernel modules from Universal Blue's akmods, which are signed with the Universal Blue key. After the first installation, you will be prompted to enroll the Secure Boot key in the BIOS.

Enter the password `universalblue` when prompted to enroll the key.

If this step is not completed during the initial setup, you can manually enroll the key by running the following command in the terminal:

```bash
ujust enroll-secure-boot-key
```

The public key can be found in the akmods repository [here](https://github.com/ublue-os/akmods/raw/main/certs/public_key.der).
If you'd like to enroll this key prior to installation or rebase, download the key and run the following:

```bash
sudo mokutil --timeout -1
sudo mokutil --import public_key.der
```

## Branding

The logo, wallpapers, boot splash and fastfetch logo are generated from [branding/generate.mjs](branding/generate.mjs). To change the colours or shapes, edit that script and re-run it (needs Node.js and Edge or Chrome):

```bash
node branding/generate.mjs
```

[build_files/base/06-branding.sh](build_files/base/06-branding.sh) replaces the Bluefin names and links that come from the shared `projectbluefin/common` layer.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Issues and pull requests are welcome at [iarsslen/amethyst](https://github.com/iarsslen/amethyst).

## Acknowledgements

Amethyst is based on [Bluefin](https://github.com/ublue-os/bluefin) by the [Universal Blue](https://universal-blue.org/) project, and it keeps building on their shared infrastructure. Thanks to the Bluefin and Universal Blue contributors for the work this project stands on.

## License

This project is licensed under the Apache License 2.0. See the [LICENSE](LICENSE) and [NOTICE](NOTICE) files for details.

### Third-Party Components

Amethyst incorporates and builds upon several open source projects:
- **Bluefin / Universal Blue**: Base images, the shared desktop layer (`projectbluefin/common`), kernel modules and build tooling
- **Fedora Linux**: Base operating system
- **GNOME Desktop Environment**: Desktop interface
- **Various CNCF Projects**: Cloud-native tooling and containers

All incorporated components keep their respective licenses and attributions.
