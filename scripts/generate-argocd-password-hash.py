#!/usr/bin/env python3
"""Prompt safely and print an Argo CD-compatible bcrypt hash."""

from getpass import getpass

from passlib.hash import bcrypt


password = getpass("Argo CD admin password: ")
confirmation = getpass("Repeat password: ")
if password != confirmation:
    raise SystemExit("Passwords do not match.")
if len(password) < 12:
    raise SystemExit("Password must be at least 12 characters.")
print(bcrypt.using(rounds=12).hash(password))
