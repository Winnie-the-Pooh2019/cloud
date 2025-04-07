import enum
import os
import time
import shutil
import hashlib
import argparse
import zipfile

parser = argparse.ArgumentParser(description="Copy files from source to destination.")
parser.add_argument("-a", "--action", required=True, help="What action should be performed.")
parser.add_argument("-d", "--destination", required=True, help="Path to the destination folder.")
parser.add_argument("-b", "--backup", required=True, help="Path to the backup folder.")
parser.add_argument("-rm", "--removeold", required=False, help="Remove old files while restoring.")

args = parser.parse_args()
action = args.action
bkp = args.backup
dist = args.destination
remove_old = args.removeold

backup_filename = 'backup'
backup_extension = 'zip'
checksum_filename = 'checksum.sha256'

checksum_filepath_bkp = f'{bkp}/{checksum_filename}'
checksum_filepath_dist = f'{dist}/{checksum_filename}'


# check - if user need to check files persistence
#    read checksum files
#       if no file found in backup folder -> backup
#       if file found in backup folder, bot noone in destination one -> get checksum of files in destination
#           if there are no files -> restore
#           if it matches the one in backup -> do nothing
#           else -> backup
# backup - if user need to back files up
#
# restore - if files' checksum file doesn't match the checksum in backup folder or user files doesn't exist at all
class Action(enum.Enum):
    check = 1
    backup = 2
    restore = 3

class RestoreException(Exception):
    pass


class OkException(Exception):
    pass


class NeedBackupException(Exception):
    pass


class NothingToBackupException(Exception):
    pass


class IncorrectRestoreException(Exception):
    pass


class UnrecognizedCommandException(Exception):
    pass


def read_file(file_path):
    if not os.path.exists(file_path):
        return None
    
    with open(file_path, 'r') as file:
        return file.read()


def write_file(content, file_path):
    with open(file_path, 'w') as file:
        file.write(content)


def remove_file(file_path):
    if os.path.exists(file_path):
        os.remove(file_path)


def get_creation_date(file_path):
    try:
        creation_time = os.path.getctime(file_path)
        return time.ctime(creation_time)
    except OSError:
        return None


def get_checksum(directory):
    if not os.listdir(directory):
        return None

    hasher = hashlib.sha256()
    for root, _, files in os.walk(directory):
        for filename in files:
            if filename == checksum_filename:
                continue

            file_path = os.path.join(root, filename)
            with open(file_path, "rb") as file:
                file_hash = hashlib.sha256(file.read()).hexdigest()
                hasher.update(file_hash.encode())

    return hasher.hexdigest()


def restore(destination, backup, remove_old=False):
    if not os.path.exists(destination):
        os.makedirs(destination)
    elif remove_old:
        for file in os.listdir(destination):
            remove_file(file)

    backup_archive = os.path.join(backup, f'{backup_filename}.{backup_extension}')
    destination_archive = os.path.join(destination, f'{backup_filename}.{backup_extension}')
    shutil.copy2(backup_archive, destination_archive)

    remove_file(checksum_filepath_dist)
    shutil.copy2(checksum_filepath_bkp, checksum_filepath_dist)

    try:
        with zipfile.ZipFile(destination_archive, "r") as archive:
            archive.extractall(destination)
    except zipfile.BadZipFile as err:
        print(f"Error: Invalid archive format. {err}")
        os.remove(destination_archive)

        raise IncorrectRestoreException

    os.remove(destination_archive)


def backup(destination, backup):
    if not os.path.exists(backup):
        os.makedirs(backup)

    if not os.path.exists(destination) or not os.listdir(destination):
        raise NothingToBackupException

    files_hash = get_checksum(dist)

    remove_file(checksum_filepath_bkp)
    remove_file(checksum_filepath_dist)

    shutil.make_archive(f'{bkp}/{backup_filename}', backup_extension, dist)

    write_file(files_hash, checksum_filepath_dist)
    write_file(files_hash, checksum_filepath_bkp)


def copy_data(source, destination):
    if not os.path.exists(source):
        raise FileNotFoundError('Source directory does not exist.')
    if not os.path.exists(destination):
        os.makedirs(destination)

    shutil.copy2(source, destination)


try:
    if action == Action.check.name:
        checksum_dist = read_file(checksum_filepath_dist)
        checksum_backup = read_file(checksum_filepath_bkp)

        if checksum_backup is None:
            if not os.listdir(dist):
                if os.path.exists(f'{bkp}/{backup_filename}.{backup_extension}'):
                    print('No files in destination folder... Restoring from backup')
                    restore(dist, bkp)
                    print('Restoring complete')
                else:
                    raise OkException
            else:
                print('No actual backup is found... Making new one')
                backup(dist, bkp)
                print('Backup performed')

        else:
            if checksum_dist is None:
                checksum_files_dist = get_checksum(dist)

                if checksum_files_dist is None:
                    print('Destination folder is empty... Restoring from backup')
                    restore(dist, bkp)
                    print('Restoring complete')
                elif checksum_files_dist == checksum_backup:
                    print('Backup checksum is equal to destination files checksum, but no destination checksum file found... Copying checksum file')
                    copy_data(checksum_filepath_bkp, dist)
                    print('Copying complete')
                else:
                    print('Backup is out of date... Making new one')
                    backup(dist, bkp)
                    print('Backup performed')

            else:
                if checksum_dist != checksum_backup or get_checksum(dist) != checksum_backup:
                    print('Backup files are out of date... Making new one')
                    backup(dist, bkp)
                    print('Backup complete')
                else:
                    if not os.path.exists(f'{bkp}/{backup_filename}.{backup_extension}'):
                        print('Checksum files found, but no archive... Making new one')
                        backup(dist, bkp)
                        print('Backup complete')
                    else:
                        raise OkException

    elif action == Action.backup.name:
        backup(dist, bkp)
        print('Backup performed')

    elif action == Action.restore.name:
        restore(dist, bkp, remove_old)
        print('Restoring performed')

    else:
        raise UnrecognizedCommandException

except OkException:
    print('Nothing to do... Exiting')
except NothingToBackupException:
    print('No files... Nothing to do')
except IncorrectRestoreException:
    print('Unsuccessful restoring exception')
except UnrecognizedCommandException:
    print('Unrecognized command... Exiting...')