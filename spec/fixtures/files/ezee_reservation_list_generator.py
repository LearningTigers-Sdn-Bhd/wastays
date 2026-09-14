#!/usr/bin/env python3
"""
Generates spec/fixtures/files/ezee_reservation_list_sample.xls -- a synthetic
eZee "Reservation List" export for the future-reservation importer.

Why this exists: the only real export the client sent covers May 2025 arrivals,
which the importer refuses in production (future arrivals only). This fixture is
the same report with future dates and 61 reservations instead of 1193, so the
importer can be exercised without a past-date override.

It reproduces the real file's layout exactly -- BIFF .xls, Crystal Reports
banner, 48 columns of merged-cell offsets, remark rows, and the Group Total /
Summary Report footer that the parser uses as its verification anchor.

Deliberate edge cases are documented in docs/ezee-reservation-import.md; keep
them when regenerating.

Requires xlwt (writes BIFF):   pip install xlwt
Regenerate when ARRIVAL dates fall into the past:
    python3 spec/fixtures/files/ezee_reservation_list_generator.py
"""

import datetime as dt
import random
from collections import defaultdict

import xlwt

# --- Anchors. Bump these when the fixture goes stale. ---------------------
PRINTED_ON = dt.datetime(2026, 9, 14, 10, 59, 42)
ARRIVAL_FROM = dt.date(2026, 10, 1)
ARRIVAL_TO = dt.date(2026, 10, 31)
HOTEL = "KINABALU PINE RESORTS SDN BH"
PRINTED_BY = "Emily"
OUT = "spec/fixtures/files/ezee_reservation_list_sample.xls"

random.seed(20260914)  # deterministic: specs may assert on exact values

# --- Inventory: the real property's 64 rooms, room -> type ---------------
ROOMS = {}
for pre in "ABCHKM":
    for i in range(1, 5):
        ROOMS[f"{pre}{i}"] = "DLX"
for pre in "DEGJL":
    for i in range(1, 5):
        ROOMS[f"{pre}{i}"] = "STD"
for i in range(1, 5):
    ROOMS[f"F{i}"] = "STD VALLEY"
    ROOMS[f"S{i}"] = "SDLX S"
ROOMS["N1"] = ROOMS["N2"] = "DLX"
ROOMS["N3"] = ROOMS["N4"] = "SDLX N"
for i in range(1, 5):
    ROOMS[f"P{i}"] = "SP STD"
ROOMS["R1"] = ROOMS["R2"] = "SP STD"
ROOMS["R3"] = ROOMS["R4"] = "STD"
assert len(ROOMS) == 64

BY_TYPE = defaultdict(list)
for room, rtype in sorted(ROOMS.items()):
    BY_TYPE[rtype].append(room)

RATES = {
    "STD": [210.00, 225.00, 290.00],
    "DLX": [290.00, 305.00, 360.00, 365.00, 370.00, 395.00],
    "SP STD": [250.00],
    "STD VALLEY": [259.00, 320.00],
    "SDLX S": [330.00],
    "SDLX N": [330.00],
}

AGENCIES = [
    "BORNEO TRAILS TOURS & TRAVEL SDN BHD",
    "MUSLIMTRAVELBUG SDN BHD",
    "HAPPY TRAILS BORNEO TOURS SDN BHD",
    "HAPPY TRAILS MALAYSIA TOURS",
    "DISCOVA DMC (MALAYSIA) SDN BHD",
    "AMAZING BORNEO TOURS & EVENTS SDN BHD",
    "AMAZING BORNEO TOURS & EVENTS  SDN BHD",      # double space
    "INTREPID TRAVEL (MALAYSIA) SDN BHD",
    "INTERPID TRAVEL (MALAYSIA) SDN BHD",           # typo
    "BAHTERA KEMBARA HOLIDAYS SDN.BHD.",            # punctuation
    "BORNEO BIRDING TOURS SDN BHD BORNEO BIRDING TOURS SDN BHD",  # doubled
    "POSTPONED-BORNEO HOLIDAY AND VEHICLES RENTAL SDN BHD",       # status prefix
    "POSTPONE AMAZING BORNEO TOURS & EVENTS SDN BHD",             # status prefix
    "MS LOW SIOW ENG",                              # person filed as agent
    "DAENG TRAVEL & TOURS SDN BHD",
    "BORNEO CALLING TOUR & TRAVEL SDN BHD",
    "ASIAN TRAILS (M) SDN BHD",
    "STICKY RICE TRAVEL",
]

PEOPLE = [
    "AARON DENNIS DASAN", "SITI NOOR HAFIDA BINTI ABDULLAH", "OOI JIA JIN",
    "DR JULIET MATTHEW", "LEE DING HAO", "INTAN SYAFIKA",
    "NORANIS SYAKIRAH BT BAKHARI", "AMY ROZELIN", "ARDY JAAFAR",
    "LIM TING TING", "MUHAMMAD NAZMIE", "FARAH LIYANA",
]
CORPORATES = ["BANK NEGARA MALAYSIA", "[MATJIN/SURAYAH]TOURMIND CORP LIMITED"]
USERS = ["Aimi", "Emily", "Mileyana M", "EMMYLYN", "HELEN P", "ARNIZATUL",
         "Nor Shakilawati"]
REMARKS = [
    "NONSMOKE, TWINBEDS", "LARGE BED, NON SMOKE", "cancel", "CXL", "IPAY88",
    "SIDE BY SIDE", "3 NIGHTS,", "PASTIKAN SAMA BILIK DGN BOOKING DIA",
    "NON-SMOKE, LARGE BED, MOUNTAIN VIEW", "FIXED TINGKAT ATAS. COD: 05.10.2026",
]

# --- Build reservations ---------------------------------------------------
held = defaultdict(list)   # room -> [(arrival, departure)]


def free(room, arrive, depart):
    return all(depart <= a or arrive >= d for a, d in held[room])


def take(rtype, arrive, depart):
    pool = BY_TYPE[rtype][:]
    random.shuffle(pool)
    for room in pool:
        if free(room, arrive, depart):
            held[room].append((arrive, depart))
            return room
    return None


rows = []
resv = 412300           # eZee reservation numbers, ascending
booked = dt.datetime(2026, 3, 2, 9, 14, 0)


def add(source, name, rtype, arrive, nights, rate_type, adults=2, children=0,
        rate=None, paid=0.00, remark=None, bump=True):
    global resv, booked
    depart = arrive + dt.timedelta(days=nights)
    room = take(rtype, arrive, depart)
    if room is None:
        return False
    if rate is None:
        rate = random.choice(RATES[rtype])
    resv += random.choice([1, 1, 1, 2]) if bump else 1   # gaps = cancellations
    booked += dt.timedelta(seconds=1)
    rows.append({
        "no": resv, "booked": booked, "source": source, "name": name,
        "arrive": arrive, "depart": depart, "adults": adults,
        "children": children, "nights": nights, "room": room, "rtype": rtype,
        "rate_type": rate_type, "total": round(rate * nights, 2), "paid": paid,
        "user": random.choice(USERS), "remark": remark,
    })
    return True


def day(n):
    return ARRIVAL_FROM + dt.timedelta(days=n - 1)


# Travel-agent blocks: the bulk, mirroring the real file's group sizes.
BLOCKS = [
    ("BORNEO TRAILS TOURS & TRAVEL SDN BHD", 3, "DLX", 6, 1, "Agent"),
    ("BORNEO TRAILS TOURS & TRAVEL SDN BHD", 9, "STD", 4, 1, "Agent"),
    ("MUSLIMTRAVELBUG SDN BHD", 12, "STD", 6, 2, "Agent"),
    ("HAPPY TRAILS BORNEO TOURS SDN BHD", 17, "DLX", 4, 1, "Agent"),
    ("DISCOVA DMC (MALAYSIA) SDN BHD", 21, "STD", 5, 1, "Agent"),
    ("AMAZING BORNEO TOURS & EVENTS SDN BHD", 24, "DLX", 3, 1, "Agent"),
    ("AMAZING BORNEO TOURS & EVENTS  SDN BHD", 24, "SP STD", 2, 1, "Agent"),
    ("INTREPID TRAVEL (MALAYSIA) SDN BHD", 9, "SDLX S", 2, 3, "Agent"),
    ("INTERPID TRAVEL (MALAYSIA) SDN BHD", 27, "DLX", 2, 1, "Agent"),
    ("DAENG TRAVEL & TOURS SDN BHD", 14, "STD", 4, 1, "Agent"),
    ("BORNEO CALLING TOUR & TRAVEL SDN BHD", 19, "DLX", 3, 2, "Agent"),
    ("BAHTERA KEMBARA HOLIDAYS SDN.BHD.", 8, "STD VALLEY", 2, 1, "Agent"),
]
for name, start, rtype, count, nights, rate_type in BLOCKS:
    for i in range(count):
        add("Travel Agent", name, rtype, day(start), nights, rate_type,
            remark=random.choice(REMARKS) if i == 0 and random.random() < 0.5
            else None)

# Travel-agent singles, including the awkward names.
add("Travel Agent", "POSTPONED-BORNEO HOLIDAY AND VEHICLES RENTAL SDN BHD",
    "STD VALLEY", day(11), 1, "Agent", remark="cancel")
add("Travel Agent", "DAENG TRAVEL & TOURS SDN BHD", "STD", day(21), 1, "Agent",
    remark="\ncancle")                            # real artefact: leading newline
add("Travel Agent", "POSTPONE AMAZING BORNEO TOURS & EVENTS SDN BHD",
    "DLX", day(23), 1, "Agent")
add("Travel Agent", "BORNEO BIRDING TOURS SDN BHD BORNEO BIRDING TOURS SDN BHD",
    "SDLX N", day(16), 4, "Agent")
add("Travel Agent", "MS LOW SIOW ENG", "STD", day(29), 1, "Agent")
add("Travel Agent", "HAPPY TRAILS MALAYSIA TOURS", "DLX", day(26), 1, "Agent")
add("Travel Agent", "ASIAN TRAILS (M) SDN BHD", "STD", day(7), 1, "Agent",
    rate=190.01)                                   # non-round discount residue
add("Travel Agent", "STICKY RICE TRAVEL", "DLX", day(13), 1, "Comp", rate=0.00)
add("Travel Agent", "DISCOVA DMC (MALAYSIA) SDN BHD", "SP STD", day(30), 1,
    "Agent", adults=3)                             # the one 3-adult row

# Direct sources carry real guest names.
for i, who in enumerate(PEOPLE[:4]):
    add("Phone Reservation", who, "STD", day(3 + i * 5), 1 + (i % 2), "Promo",
        paid=290.00 if i == 0 else 0.00)
add("Internet Reservation", PEOPLE[4], "DLX", day(20), 1, "Pub", paid=305.00)
add("Walk In", PEOPLE[5], "STD", day(2), 1, "Pub", adults=1, paid=210.00)
add("Over-The-Counter", PEOPLE[6], "SP STD", day(25), 1, "Pub", adults=1)
add("Corporate", CORPORATES[0], "DLX", day(15), 2, "Corp")
add("Corporate", CORPORATES[1], "DLX", day(15), 1, "Corp",
    children=1)                                    # synthetic: real file is all 0

# OTA rows: some named, most blank (eZee prints "- SOURCE" when empty).
add("OTA (KPR ONLINE)", PEOPLE[7], "DLX", day(10), 1, "Promo", paid=360.00)
add("OTA (KPR ONLINE)", PEOPLE[8], "STD", day(22), 1, "Promo")
for d in (5, 18, 28):
    add("OTA (KPR ONLINE)", "- KPR ONLINE", "DLX", day(d), 1, "Promo",
        paid=305.00 if d == 5 else 0.00)
add("AGODA", PEOPLE[9], "STD", day(9), 2, "Agoda", paid=450.00)
for d in (12, 26):
    add("AGODA", "- AGODA", "DLX", day(d), 1, "Agoda", paid=370.00)
add("TIKET.COM", "- TIKET.COM", "STD", day(17), 1, "TIKET", paid=225.00)

rows.sort(key=lambda r: r["no"])
print(f"{len(rows)} reservations")

# --- Write the sheet ------------------------------------------------------
bold = xlwt.easyxf("font: bold on")
book = xlwt.Workbook(encoding="utf-8")
sh = book.add_sheet("Sheet1")


def put(r, c, val, style=None):
    sh.write(r, c, val, style) if style else sh.write(r, c, val)


fmt = "%d-%b-%y"
put(0, 2, "Printed By :"); put(0, 3, HOTEL)
put(2, 4, PRINTED_BY); put(2, 44, "Page :"); put(2, 47, 1.0)
put(3, 2, "Printed Date :"); put(3, 4, "Reservation List", bold)
put(4, 4, PRINTED_ON.strftime("%d-%b-%y %I:%M:%S %p"))
put(7, 2, f"Arrival Date {ARRIVAL_FROM.strftime(fmt)} To "
          f"{ARRIVAL_TO.strftime(fmt)}")

HEADERS = [
    (2, "Rsrv. No"), (5, "Rsrv. Date"), (10, "Source"), (16, "Guest Name"),
    (23, "Arrival"), (26, "Departure"), (28, "Pax"), (30, "(A/C)"),
    (33, "Nights"), (35, "Room No"), (37, "Room Type"), (38, "Rate Type"),
    (40, "Total Amt."), (42, "Amt. Paid"), (46, "User"),
]
for col, label in HEADERS:
    put(9, col, label, bold)
put(11, 2, "Reason", bold); put(11, 44, "Date", bold)
put(13, 2, "Active Reservation", bold)

r = 14
for row in rows:
    put(r, 2, str(row["no"]))
    put(r, 5, row["booked"].strftime("%d-%b-%y %H:%M:%S"))
    put(r, 10, f'{row["source"]} -')
    put(r, 16, row["name"])
    put(r, 23, row["arrive"].strftime(fmt) + " 14:00:00")
    put(r, 26, row["depart"].strftime(fmt))
    put(r, 28, str(row["adults"])); put(r, 30, "/")
    put(r, 31, str(row["children"])); put(r, 33, str(row["nights"]))
    put(r, 35, row["room"]); put(r, 37, row["rtype"]); put(r, 38, row["rate_type"])
    put(r, 40, f'{row["total"]:.2f}'); put(r, 42, f'{row["paid"]:.2f}')
    put(r, 46, row["user"])
    if row["remark"]:
        put(r + 3, 2, row["remark"])
        r += 5
    else:
        r += 4

# Footer, mirroring the real file's offsets exactly.
n = len(rows)
nights = sum(x["nights"] for x in rows)
adults = sum(x["adults"] for x in rows)
children = sum(x["children"] for x in rows)
total = round(sum(x["total"] for x in rows), 2)
paid = round(sum(x["paid"] for x in rows), 2)

r += 1
put(r, 1, "Group Total :", bold); put(r, 10, float(n)); put(r, 28, float(adults))
put(r, 30, "/"); put(r, 31, float(children)); put(r, 33, float(nights))
put(r, 40, total); put(r, 42, paid)
r += 3
put(r, 2, "Grand Total :", bold); put(r, 42, paid)
put(r + 1, 40, total)
r += 4
put(r, 2, "Summary Report", bold)
r += 2
put(r, 2, "Business Source", bold); put(r, 8, "Total Nights Reserved", bold)
put(r, 18, "Rooms", bold); put(r, 21, "Adults", bold); put(r, 26, "Children", bold)
r += 2
put(r, 2, "Active Reservation", bold)
r += 2
by_src = defaultdict(lambda: [0, 0, 0, 0])
for x in rows:
    b = by_src[x["source"]]
    b[0] += x["nights"]; b[1] += 1; b[2] += x["adults"]; b[3] += x["children"]
for src in sorted(by_src):
    nn, rr, aa, cc = by_src[src]
    put(r, 2, f"{src} -"); put(r, 9, float(nn)); put(r, 18, float(rr))
    put(r, 21, float(aa)); put(r, 26, float(cc))
    r += 1
r += 2
put(r, 2, "Group Total :", bold); put(r, 8, float(nights)); put(r, 18, float(n))
put(r, 21, float(adults)); put(r, 26, float(children))
r += 2
put(r, 26, float(children))
r += 1
put(r, 2, "Grand Total :", bold); put(r, 8, float(nights)); put(r, 18, float(n))
put(r, 21, float(adults))

book.save(OUT)
print(f"wrote {OUT}")
print(f"  nights={nights} adults={adults} children={children} "
      f"total={total:.2f} paid={paid:.2f}")
