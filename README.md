# What you'll get

This is a guide intended for anyone who wants to encrypt their Steam Deck.

## Why encrypt the deck

Unlike all mobile devices of today (phones, laptops, tablets), the Steam Deck has no encryption.

In particular a malicious actor can get access to -

1. Your Steam account authentication.
   - They can buy games if you have funds or cards linked,
   - impersonate you to scam your friends,
   - engage in cheating, and risk your account in other ways.
2. Your credentials.
   - If you ever used a browser in KDE and logged in to online accounts, they may also be compromised.

Note: You can (and should) activate the security lock inbuilt to Steam Deck's UI. But that does not encrypt the storage - and it is extremely easy for anyone to take the SSD or MMC out and access your data directly.

If you follow this guide through, your Steam deck will be more secure, and it will make it very difficult (if not impossible) for bad actors to get access to accounts you have logged in to.

## What to expect after completion

After encryption through this guide -
- Every time you reboot, or power off and restart, you will require to enter a password to unlock the filesystem -
  - Though you can continue without password (see next point), it is recommended that you always decrypt to load the encrypted container before using your device for convenience and safety.
- If you continue without entering the password -
  - Your device will still be usable; you can still log in to Steam, open KDE etc.
  - But your session will operate without encryption.
  - And your data may be accessible by anyone who gets hold of your Deck afterwards.
- If you forget your password -
  - Your encrypted data will not be recoverable.
  - You can choose to delete the encrypted container and essentially revert to original state, or to re-encrypt.

## Prior Work

This project is very similar to the one here -
https://github.com/Ethorbit/SteamDeck-SteamOS-Guides/tree/main/Encrypting-With-LUKS

I am indebted to the owner trying a similar approach before. I think there are certain aspects that inspired me, and showed that I am going in the right direction.

I recommend going there to watch the video, because the video is very much representative of how this will end up. There are differences in the setup process however. This workflow should be (a) possible to do without having to repartition and (b) more compatible with all future Steam updates.

## Features

1. Security: `/home/deck` and swapfile will be encrypted.
2. Security: Any inserted sd card (optionally) can be fully encrypted.
3. **Convenience: Set up is seamless, does not need repartitioning**.
4. Convenience + Functionality: This should not break future SteamOS or SteamUI updates.
5. Functionality: Allows btrfs. (Does not mean I'm recommending it; the decision should be yours to choose ext4 or btrfs. Having said that I think there are some nice benefits to btrfs; as well as some things to keep in mind.)
6. Functionality: Requires password to decrypt. I personally prefer this over TPM, I think it's more secure.

## Known Issues

1. **Issue: Needs a throwaway account** so that we get access to Steam UI's on-screen keyboard, to type the password needed to mount the encrypted container.
2. **Issue: Trim does not work yet** on the encrypted container. This may be an issue which will be fixed with the new kernel, see https://github.com/ValveSoftware/SteamOS/issues/1101


# Before you start

## Disclaimer

As with every DIY project, things can go wrong. If you choose to follow this guide, please do so on your own responsibility.

## General Notes on the Process

That said, I think the steps outlined here are pretty safe.

Up until the point where you choose to erase data from unencrypted partition, the process is very easily reversible.

## What you need

- Either ssh access to your Steam Deck, or to connect it to a monitor and keyboard.
  - Note: I personally prefer ssh. It is more convenient since you can always get a terminal open even when Steam UI is running, eliminating the need to switch to Plasma / KDE for edits. However, this guide doesn't need it and you should be fine with Keyboard+Mouse+Display connected to your Deck.
- A secondary / throwaway Steam account (which will not be protected).
- Free space to create encrypted container.
  - I would recommend ~80-90% of the home directory space to be encrypted. You will need this much space to be freed.
  - If needed, uninstall some games (and re-install after encryption).

# Setup Process (follow this section to encrypt!)

The set up process is generally safe. However, please understand the process first before going through it.

## Step 0: Unblacklist tpm

1. Remove `blackist=tpm` from /etc/default/grub. This is needed to be able to use encryption with LUKS.
2. Run `sudo update-grub` and reboot.

NOTE: After you have done this once, every time Steam OS updates you will need to run only step 2 above.

## Step 1: Create an encrypted container, and copy your home to it

Run the lines below as root.

Either enter super user `sudo su -`, or prefix `sudo` to each of the lines as you execute them.

```sh
cd /home

# Choose a size depending on your SSD.
# This will replace your home, which will contain entire steam installation,
# and games that you install in the SSD.
# This can be increased (or even decreased); but those operations require expertise.
# So try to choose a size that will serve you for a long time.
# I chose 750G for a 1TB.
fallocate -l 750G ./container
cryptsetup luksFormat ./container
cryptsetup open ./container deck_alt

# You can choose btrfs too, if you want.
mkfs.ext4 /dev/mapper/deck_alt
tune2fs -m 1 /dev/mapper/deck_alt

# Allow discards for fstrim.
cryptsetup --allow-discards --persistent refresh /dev/mapper/deck_alt

mkdir /run/mount/deck_alt  # Temporary one-time mount.
chown deck:deck /run/mount/deck_alt
mount /dev/mapper/deck_alt /run/mount/deck_alt

rsync -aAXHSv /home/deck/ /run/mount/deck_alt/
```

## Step 2: Set up the unlock scripts

Add these scripts to your current (non-encrypted) home -

### Create ~/unlocker/runasroot.sh

The idea is to run `sudo ~/unlocker/runasroot.sh` on every boot to unlock the container and replace your `home/deck` with an the encrypted filesystem.

```sh
#!/bin/bash
set -ueo pipefail

echo -n Password:
read -s PASS
echo

readonly PASSFILE=$(mktemp /tmp/runasroot_XXXXXXXX)
trap "rm -f $PASSFILE" EXIT
echo $PASS > $PASSFILE

set -x

readonly SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Encrypt swap.
# Note: After this is run once, swap will not mount for the unencrypted partition.
# To revert, simply execute `mkswap /home/swapfile`.
if [[ ! -e /dev/mapper/swap ]]; then
  swapoff -a
  cryptsetup open /home/swapfile swap --type=plain --cipher=aes-xts-plain64 --key-file=/dev/urandom
  mkswap /dev/mapper/swap
  swapon /dev/mapper/swap
fi

# # Optionally decrypt sd card with the same password.
# # You will need to write a script similar to this one, and call it like the line below.
# $SCRIPT_DIR/mount_sd_games.sh $PASSFILE

# Unlock home.
cat $PASSFILE | cryptsetup open /home/container deck_alt -

# Change /home/deck with the unlocked container.
mount /dev/mapper/deck_alt /home/deck

# Run optional user ~/decrypt_startup.sh if present in the unlocked home.
# This can be used to start your own services or carry out any maintainence on unlock.
readonly OPTIONAL_STARTUP_SCRIPT=/home/deck/decrypt_startup.sh
if [[ -f $OPTIONAL_STARTUP_SCRIPT ]]; then
  # Need to set a few variabls, otherwise systemctl --user does not work.
  # See https://askubuntu.com/questions/1007055/systemctl-edit-problem-failed-to-connect-to-bus
  USER_XDG_DIR=/run/user/1000
  sudo su - deck <<EOF
  set -x
  export XDG_RUNTIME_DIR=${USER_XDG_DIR}
  export DBUS_SESSION_BUS_ADDRESS="unix:path=${USER_XDG_DIR}/bus"
  $OPTIONAL_STARTUP_SCRIPT
EOF
  # Note: Do not indent the EOF line above!
fi

# For convenience, keep the unencrypted home mounted in some location to maintain access to it.
readonly ORIGINAL_HOME=/run/mount/_home_dirs_orig
# See https://unix.stackexchange.com/questions/4426/access-to-original-contents-of-mount-point
# Note: This must be done _after_ we mount the replacement and not before.
mkdir -p $ORIGINAL_HOME
mount --bind /home $ORIGINAL_HOME
ln -s $ORIGINAL_HOME/deck $(dirname $ORIGINAL_HOME)/_deck_orig

# Restarts gamescope compositor and steam.
systemctl restart sddm
```

### Create ~/unlocker/unlock.sh

This is to add a wrapper to show terminal on Steam deck, which you'll need to type the password in.

```sh
#!/bin/bash
# Add to steam as a shortcut.

set -uexo pipefail

readonly SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

xterm -e "sudo $SCRIPT_DIR/runasroot.sh"
```

Add this to Steam as a shortcut.

If everything works, when you start it, you will be asked for two passwords.
First one is for your user, second for the encrypted drive. Once you pass both of them, Steam will restart using the newly encrypted home.

### Confirm that it works

- Change something locally on your Steam, e.g. uninstall a game.
- Start the unlock.sh and follow the instructions.
- You should see Steam restart, and your uninstalled game is still there (because it restarts into the encrypted container where the game is still present).


## Step 3: Housekeeping

If you complete Step 2 successfully, you're pretty much done. You will now want to clean up original data left in unencrypted partition, and encrypt the swap.

### 3A. Log out and delete un-needed files from the unencrypted partition

NOTE: Some of these are irreversible, so please be extra careful that you are doing it on the right partition.

Do the following **before you decrypt** -
1. Delete your unencrypted data
    - Delete `~/.var/app/*` which contains settings and authentication for apps you installed through Discover.
    - Uninstall all installed games.
    - Remove bash history -
      - Add `HISTFILE=` to the end of `~/.bash_profile`
      - Remove `~/.bash_history`
2. Log in with a throwaway steam account.
3. Log _out_ your perimary account.
4. You may need to add a link to the unlock script again.

Reboot and verify decryption still works.

### 3B. Notes on encrypted swap

Swap will be encrypted when you unlock the deck.

- For additional safety, consider deleting existing swap to remove any existing data in it, and recreate -

```sh
sudo swapoff -a
sudo rm /home/swapfile
# Note: 1G is the default swap size that Steam OS comes with.
# If you want to use a different size, you can change it below.
sudo fallocate -l 1G /home/swapfile
sudo chmod 600 /home/swapfile

# Then reboot.
# You can verify that swap is active after reboot, by running `swapon -s`.
```

- Only if you ever revert encryption, run `sudo mkswap /home/swapfile` to let the unencrypted swapfile to be used again.

# Post Encryption

Every time you get a SteamOS update, you need to do the following -
- Run: `sudo upgrade-grub` from a console in Desktop mode before you unlock, and reboot.
  - Explanation why:
    - Without this, unlocking will not succeed since SteamOS needs to load the tpm module.
    - (Development TODO: This step can be removed; I need to chage the script to check if upgrade is needed, and if so then do it.)

# Conclusion: Status & Future

## Status

This setup is very non-intrusive and compatible with the partition structure.

As a result, this way of encrypting may be a viable option for Steam to roll out for existing users seamlessly.

## What Steam can do better

- Remove the need of a throw-away Steam account
  - A throwaway account is used only to get access to start the Steam UI, so that we get access to the on-screen keyboard to type in a password.
- Show unlock prompt without user action
  - The need to click on the unlock script manually may be removed if Steam UI can always show it when the disk is encrypted.
- Add TPM support
  - The unlock prompt may be skipped altogether. Note that I think this is less secure, and I personally prefer to type in my own password, and will not use this.

# FAQ

- Q: Is this full disk encryption?
  - A: No. This only encrypts your `/home/deck` directory.
- Q: I set it up, but forgot the password. Can you help?
  - A: There is no way to recover the data without password.
  - Assuming you are okay to lose your data, it is fairly trivial to delete the `/home/container` file to free up the space. Then if you want, you can continue to use it unencrypted, or go through the process again to re-encrypt.
- Q: I don't want to read and understand technical details. Will you publish a script to do this automatically?
  - A: The whole process stated here should be fairly easy to automate. However, automation must be done carefully to make it as foolproof as possible. I may work on it, but I cannot give an ETA given that my day job is demanding.
- Q: Should I also set up Security lock screen from Steam UI settings?
  - A: Yes! The Steam UI's security features nicely complements encryption. If you don't have it on, anyone getting access of your Deck while it is powered on will be able to access to your unlocked data.
- Q: I need feature X OR I have other questions.
  - A: Please open an issue in this github project. Either myself or someone else from the community will try to help. Covnersely, if you see an issue which we can help with, you are encouraged to do so.
