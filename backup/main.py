import os
import time
import shutil
import hashlib
import argparse
import zipfile
import re
import glob
from datetime import datetime

backup_filename = 'backup'
backup_extension = 'zip'
checksum_filename = 'checksum.sha256'

class RestoreException(Exception):
    pass


class CopyException(Exception):
    pass


class NothingToBackupException(Exception):
    pass


class ChecksumIsActualException(Exception):
    pass


class BackupActualException(Exception):
    pass


class NeedBackupException(Exception):
    pass


def read_file(file_path):
    if not os.path.exists(file_path):
        return None
    
    with open(file_path, 'r') as file:
        return file.read()


def get_creation_date(file_path):
    try:
        creation_time = os.path.getctime(file_path)
        return time.ctime(creation_time)
    except OSError:
        return None


def get_checksum(directory):
    hasher = hashlib.sha256()
    for root, _, files in os.walk(directory):
        for filename in files:
            file_path = os.path.join(root, filename)
            with open(file_path, "rb") as file:
                file_hash = hashlib.sha256(file.read()).hexdigest()
                hasher.update(file_hash.encode())

    return hasher.hexdigest()


def restore(destination, backup):
    if not os.path.exists(destination):
        os.makedirs(destination)

    source_archive = os.path.join(backup, f'{backup_filename}.{backup_extension}')
    destination_archive = os.path.join(destination, f'{backup_filename}.{backup_extension}')

    shutil.copy2(source_archive, destination_archive)

    try:
        with zipfile.ZipFile(destination_archive, "r") as archive:
            archive.extractall(destination)
    except zipfile.BadZipFile as err:
        print(f"Error: Invalid archive format. {err}")
        os.remove(destination_archive)
        return

    os.remove(destination_archive)


def backup(destination, backup):
    pass


def copy_data(source, destination):
    if not os.path.exists(source):
        raise FileNotFoundError('Source directory does not exist.')
    if not os.path.exists(destination):
        os.makedirs(destination)

    shutil.copytree(source, destination, dirs_exist_ok=True)  # Continue if destination dirs exist


parser = argparse.ArgumentParser(description="Copy files from source to destination.")
parser.add_argument("-a", "--action", required=True, help="What action should be performed.")
parser.add_argument("-s", "--source", required=True, help="Path to the source folder.")
parser.add_argument("-d", "--destination", required=True, help="Path to the destination folder.")
parser.add_argument("-b", "--backup", required=True, help="Path to the backup folder.")

args = parser.parse_args()
action = args.action
src = args.source
bkp = args.backup
dist = args.destination

backup_file = f'{bkp}/{backup_filename}.{backup_extension}'
checksum_filepath_bkp = f'{bkp}/{checksum_filename}'
checksum_filepath_dist = f'{dist}/{checksum_filename}'
backup_filepath = f'{bkp}/{backup_filename}.{backup_extension}'

if action == 'check':
    try:
        try:
            if os.listdir(dist):

                checksum_content = read_file(checksum_filepath_bkp)
                checksum_dist = read_file(checksum_filepath_dist)

                if os.path.exists(backup_filepath) and checksum_content is not None and checksum_dist is not None and checksum_content == checksum_dist:
                    raise BackupActualException

                if  checksum_content != checksum_dist:
                    if get_creation_date(checksum_filepath_bkp) < get_creation_date(checksum_filepath_dist):
                        raise NeedBackupException
                    else:
                        raise RestoreException



                    try:
                        with zipfile.ZipFile(backup_filepath) as z:
                            with z.open(checksum_filename, 'r') as checksum_file:
                                backup_checksum = checksum_file.read()
                    except (zipfile.BadZipFile, FileNotFoundError) as e:
                        backup_checksum = '-1'

                    try:
                        with open(f'{dist}/{checksum_filename}', 'rb') as checksum_file:
                            dist_checksum = checksum_file.read()
                    except FileNotFoundError:
                        dist_checksum = '-1'

                    if backup_checksum != '-1' and backup_checksum != dist_checksum:
                        raise RestoreException
                else:
                    if not os.listdir(dist):
                        raise CopyException
            else:
                if os.path.exists(backup_filepath):
                    raise RestoreException
                else:
                    raise CopyException
        except RestoreException:
            print('Data is not actual... Restoring...')
            restore(dist, bkp)
        except NeedBackupException:
            print('Data in backup is not actual... Backuping')
            backup(dist, bkp)
    except BackupActualException as e:
        print('Backup is actual... Nothing to do')
    except FileNotFoundError as e:
        print(f'{e}')
    except Exception as e:
        print('Unexpected error:', e)
elif action == 'backup':
    try:
        if not os.listdir(dist):
            raise NothingToBackupException

        content_hash = get_checksum(dist)

        if content_hash is not None and content_hash == read_file(checksum_filepath_bkp):
            raise ChecksumIsActualException

        with open(checksum_filepath_bkp, "w") as checksum_file:
            checksum_file.write(content_hash)

        archived = shutil.make_archive(backup_filepath, backup_extension, dist)

        print('Backup completed')
    except ChecksumIsActualException:
        print('Checksum is actual... Nothing to backup')
    except NothingToBackupException:
        print('Backup failed. Nothing to backup')
    except Exception as e:
        print('Unexpected error:', e)
else:
    print('Invalid action')