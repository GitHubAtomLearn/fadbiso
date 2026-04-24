# Fedora Atomic Desktops Bootable Container Images Based ISOs

> [!NOTE]
> This experimental project aims to demonstrate how to build ISO files from an Atomic Desktops bootable container images for learning and testing purposes.<br />
> This is an independent project and is **not affiliated with, endorsed by, or officially supported by the Fedora Project** in any way.

## Prerequisites

- **Podman** (for container operations)
- **`just`** (command runner; install with `dnf install just`)
- **Root access** (required for building images and ISOs)
- Sufficient disk space (~10GB+) for container builds and ISO generation

## Building Container Images

### Recipe: `container`

**Parameters:**
- `type` (required): Build image type — `installer` or `live`
- `variant` (required): Desktop variant — `silverblue` or `kinoite`
- `repo` (optional): Base image repository — `standard` or `sealed` (defaults to `standard`)
- `version` (optional): Fedora version — `44` or `45` (defaults to `44`)

**Examples:**

Build a Silverblue installer container from the standard repository:

```bash
sudo just container installer silverblue
```

Build a Kinoite live container from the sealed repository for Fedora 45:

```bash
sudo just container live kinoite sealed 45
```

## Building ISOs

### Recipe: `iso`

**Parameters:**
- `variant` (required): Desktop variant — `silverblue` or `kinoite`
- `version` (optional): Fedora version — `44` or `45` (defaults to `44`)

> [!IMPORTANT]
> You must build the container image before building the ISO. The `iso` recipe references the container image built by the `container` recipe. If you try to build an ISO for a version where no container image exists, the build will fail.

**Below is an example workflow for creating an installation ISO for Fedora Silverblue 45.**

Build container for Fedora 45:

```bash
sudo just container installer silverblue 45
```

Now you can build the ISO for Fedora 45:

```bash
sudo just iso silverblue 45
```

The generated ISO will be located in the `output` directory.

## Repository Sources

### Standard: [quay.io/fedora-ostree-desktops](https://quay.io/organization/fedora-ostree-desktops)

Used when `repo` is omitted or explicitly set to `standard`. For standard Fedora Atomic Desktops builds.

### Sealed: [quay.io/fedora-atomic-desktops-sealed](https://quay.io/organization/fedora-atomic-desktops-sealed)

Used when `repo` is set to `sealed`. For security-hardened builds.

**Example:**

```bash
sudo just container live silverblue sealed
```

> [!IMPORTANT]
> Currently, Live ISOs built with the `live` type do not contain an OS installer (i.e., Anaconda). They are meant to be used primarily for manually installing Sealed Atomic Desktops variants at this time.

> [!IMPORTANT]
> Currently, ISOs built with the `installer` type will fail to install Sealed variants. For building ISOs to install Sealed variants, refer to the **Complete Sealed Variants Installation Workflow Example** below.

## Complete Sealed Variants Installation Workflow Example

> [!NOTE]
> The installation process is currently manual and requires running commands in a live environment.

1. Build a container image for the Live ISO:

   ```bash
   sudo just container live silverblue sealed
   ```

2. Build an ISO from the container image:

   ```bash
   sudo just iso silverblue
   ```

3. The generated ISO will be in the `output` directory. Write it to a USB flash drive and boot the machine from it.

> [!CAUTION]
> **The target device will be completely wiped and all existing data will be permanently lost.**

> [!IMPORTANT]
> Substitute `/dev/sda` with the actual target block device you want to install to.

4. Open a terminal and execute the installation command:

   ```bash
   sudo bootc \
       install \
       to-disk \
       --wipe \
       --filesystem btrfs \
       --composefs-backend \
       --bootloader=systemd \
       --source-imgref=registry:quay.io/fedora-atomic-desktops-sealed/silverblue:44 \
       --target-imgref=quay.io/fedora-atomic-desktops-sealed/silverblue:44 \
       /dev/sda
   ```

### Secure Boot

If you want to enroll your Secure Boot keys in your firmware, refer to [sbctl](https://github.com/Foxboron/sbctl). Detailed instructions on how to do this will be added soon.
