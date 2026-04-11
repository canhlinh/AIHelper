#!/usr/bin/env python3
"""AIHelper launcher – imports and runs aihelper.main."""

import sys
import os

# Ensure the directory containing this file is on sys.path so that the
# `aihelper` package can be imported regardless of the working directory.
_here = os.path.dirname(os.path.abspath(__file__))
if _here not in sys.path:
    sys.path.insert(0, _here)

from aihelper.main import main

if __name__ == "__main__":
    main()
