#!/usr/bin/env python

import pandas as pd
import httpx
import json
import csv
import sys
from time import sleep

filename = "mal-completed"
infile = f"{filename}-presorted.csv"
outfile = f"{filename}-presorted.csv"


def presort():

    print("Hello from a Nix-built container")
    sys.exit("goodbye")

    df = pd.read_csv(infile)
    # df.drop(columns=df.filter("State"), axis=1, inplace=True)
    with httpx.Client(
        base_url="https://api.jikan.moe/v3/anime", timeout=None
    ) as client:

        def get_english_title(x):
            sleep(0.5)
            title = (
                client.get(str(x)).json()["title_english"]
                or df.loc[df["ID"] == x]["Media"].values[0]
                or "NA"
            )
            print(title)
            return title

        # print([get_english_title(i) for i in df["ID"] if sleep(1) is None])
        if "Title_en" not in df.columns:
            df["Title_en"] = [get_english_title(i) for i in df["ID"]]
            df.to_csv(outfile, index=False, quoting=csv.QUOTE_ALL)

    comparisons = pd.read_csv(
        "../tests/import/mal-completed-comparisons", parse_dates=[1]
    )
    comparisons["timestamp"] = pd.to_datetime(comparisons["timestamp"])
    print(comparisons.info())
    comparisons.to_feather("./tests/import/mal-completed-comparisons.feather")
    # df = pd.read_feather("./tests/import/mal-completed-comparisons.feather")


if __name__ == "__main__":
    presort()
