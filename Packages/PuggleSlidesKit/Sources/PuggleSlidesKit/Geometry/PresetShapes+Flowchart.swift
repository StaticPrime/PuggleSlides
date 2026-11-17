// DrawingML preset shapes, transcribed from ECMA-376 Part 1's presetShapeDefinitions.xml. See PresetShapeDefinition
// for the statement syntax and the errata fixed.

extension PresetShapeSource {
    static let flowchart: [String: String] = [
        "flowChartAlternateProcess": """
            gd x2 +- r 0 ssd6
            gd y2 +- b 0 ssd6
            gd il */ ssd6 29289 100000
            gd ir +- r 0 il
            gd ib +- b 0 il
            cxn 3cd4 hc t
            cxn cd2 l vc
            cxn cd4 hc b
            cxn 0 r vc
            rect il il ir ib
            path
            M l ssd6
            A ssd6 ssd6 cd2 cd4
            L x2 t
            A ssd6 ssd6 3cd4 cd4
            L r y2
            A ssd6 ssd6 0 cd4
            L ssd6 b
            A ssd6 ssd6 cd4 cd4
            Z
            """,
        "flowChartCollate": """
            gd ir */ w 3 4
            gd ib */ h 3 4
            cxn 3cd4 hc t
            cxn 3cd4 hc vc
            cxn cd4 hc b
            rect wd4 hd4 ir ib
            path w=2 h=2
            M 0 0
            L 2 0
            L 1 1
            L 2 2
            L 0 2
            L 1 1
            Z
            """,
        "flowChartConnector": """
            gd idx cos wd2 2700000
            gd idy sin hd2 2700000
            gd il +- hc 0 idx
            gd ir +- hc idx 0
            gd it +- vc 0 idy
            gd ib +- vc idy 0
            cxn 3cd4 hc t
            cxn 3cd4 il it
            cxn cd2 l vc
            cxn cd4 il ib
            cxn cd4 hc b
            cxn cd4 ir ib
            cxn 0 r vc
            cxn 3cd4 ir it
            rect il it ir ib
            path
            M l vc
            A wd2 hd2 cd2 cd4
            A wd2 hd2 3cd4 cd4
            A wd2 hd2 0 cd4
            A wd2 hd2 cd4 cd4
            Z
            """,
        "flowChartDecision": """
            gd ir */ w 3 4
            gd ib */ h 3 4
            cxn 3cd4 hc t
            cxn cd2 l vc
            cxn cd4 hc b
            cxn 0 r vc
            rect wd4 hd4 ir ib
            path w=2 h=2
            M 0 1
            L 1 0
            L 2 1
            L 1 2
            Z
            """,
        "flowChartDelay": """
            gd idx cos wd2 2700000
            gd idy sin hd2 2700000
            gd ir +- hc idx 0
            gd it +- vc 0 idy
            gd ib +- vc idy 0
            cxn 3cd4 hc t
            cxn cd2 l vc
            cxn cd4 hc b
            cxn 0 r vc
            rect l it ir ib
            path
            M l t
            L hc t
            A wd2 hd2 3cd4 cd2
            L l b
            Z
            """,
        "flowChartDisplay": """
            gd x2 */ w 5 6
            cxn 3cd4 hc t
            cxn cd2 l vc
            cxn cd4 hc b
            cxn 0 r vc
            rect wd6 t x2 b
            path w=6 h=6
            M 0 3
            L 1 0
            L 5 0
            A 1 3 3cd4 cd2
            L 1 6
            Z
            """,
        "flowChartDocument": """
            gd y1 */ h 17322 21600
            gd y2 */ h 20172 21600
            cxn 3cd4 hc t
            cxn cd2 l vc
            cxn cd4 hc y2
            cxn 0 r vc
            rect l t r y1
            path w=21600 h=21600
            M 0 0
            L 21600 0
            L 21600 17322
            C 10800 17322 10800 23922 0 20172
            Z
            """,
        "flowChartExtract": """
            gd x2 */ w 3 4
            cxn 3cd4 hc t
            cxn cd2 wd4 vc
            cxn cd4 hc b
            cxn 0 x2 vc
            rect wd4 vc x2 b
            path w=2 h=2
            M 0 2
            L 1 0
            L 2 2
            Z
            """,
        "flowChartInputOutput": """
            gd x3 */ w 2 5
            gd x4 */ w 3 5
            gd x5 */ w 4 5
            gd x6 */ w 9 10
            cxn 3cd4 x4 t
            cxn 3cd4 hc t
            cxn cd2 wd10 vc
            cxn cd4 x3 b
            cxn cd4 hc b
            cxn 0 x6 vc
            rect wd5 t x5 b
            path w=5 h=5
            M 0 5
            L 1 0
            L 5 0
            L 4 5
            Z
            """,
        "flowChartInternalStorage": """
            cxn 3cd4 hc t
            cxn cd2 l vc
            cxn cd4 hc b
            cxn 0 r vc
            rect wd8 hd8 r b
            path w=1 h=1 stroke=false extrusionOk=false
            M 0 0
            L 1 0
            L 1 1
            L 0 1
            Z
            path w=8 h=8 fill=none extrusionOk=false
            M 1 0
            L 1 8
            M 0 1
            L 8 1
            path w=1 h=1 fill=none
            M 0 0
            L 1 0
            L 1 1
            L 0 1
            Z
            """,
        "flowChartMagneticDisk": """
            gd y3 */ h 5 6
            cxn 3cd4 hc hd3
            cxn 3cd4 hc t
            cxn cd2 l vc
            cxn cd4 hc b
            cxn 0 r vc
            rect l hd3 r y3
            path w=6 h=6 stroke=false extrusionOk=false
            M 0 1
            A 3 1 cd2 cd2
            L 6 5
            A 3 1 0 cd2
            Z
            path w=6 h=6 fill=none extrusionOk=false
            M 6 1
            A 3 1 0 cd2
            path w=6 h=6 fill=none
            M 0 1
            A 3 1 cd2 cd2
            L 6 5
            A 3 1 0 cd2
            Z
            """,
        "flowChartMagneticDrum": """
            gd x2 */ w 2 3
            cxn 3cd4 hc t
            cxn cd2 l vc
            cxn cd4 hc b
            cxn 0 x2 vc
            cxn 0 r vc
            rect wd6 t x2 b
            path w=6 h=6 stroke=false extrusionOk=false
            M 1 0
            L 5 0
            A 1 3 3cd4 cd2
            L 1 6
            A 1 3 cd4 cd2
            Z
            path w=6 h=6 fill=none extrusionOk=false
            M 5 6
            A 1 3 cd4 cd2
            path w=6 h=6 fill=none
            M 1 0
            L 5 0
            A 1 3 3cd4 cd2
            L 1 6
            A 1 3 cd4 cd2
            Z
            """,
        "flowChartMagneticTape": """
            gd idx cos wd2 2700000
            gd idy sin hd2 2700000
            gd il +- hc 0 idx
            gd ir +- hc idx 0
            gd it +- vc 0 idy
            gd ib +- vc idy 0
            gd ang1 at2 w h
            cxn 3cd4 hc t
            cxn cd2 l vc
            cxn cd4 hc b
            cxn 0 r vc
            rect il it ir ib
            path
            M hc b
            A wd2 hd2 cd4 cd4
            A wd2 hd2 cd2 cd4
            A wd2 hd2 3cd4 cd4
            A wd2 hd2 0 ang1
            L r ib
            L r b
            Z
            """,
        "flowChartManualInput": """
            cxn 3cd4 hc hd10
            cxn cd2 l vc
            cxn cd4 hc b
            cxn 0 r vc
            rect l hd5 r b
            path w=5 h=5
            M 0 1
            L 5 0
            L 5 5
            L 0 5
            Z
            """,
        "flowChartManualOperation": """
            gd x3 */ w 4 5
            gd x4 */ w 9 10
            cxn 3cd4 hc t
            cxn cd2 wd10 vc
            cxn cd4 hc b
            cxn 0 x4 vc
            rect wd5 t x3 b
            path w=5 h=5
            M 0 0
            L 5 0
            L 4 5
            L 1 5
            Z
            """,
        "flowChartMerge": """
            gd x2 */ w 3 4
            cxn 3cd4 hc t
            cxn cd2 wd4 vc
            cxn cd4 hc b
            cxn 0 x2 vc
            rect wd4 t x2 vc
            path w=2 h=2
            M 0 0
            L 2 0
            L 1 2
            Z
            """,
        "flowChartMultidocument": """
            gd y2 */ h 3675 21600
            gd y8 */ h 20782 21600
            gd x3 */ w 9298 21600
            gd x4 */ w 12286 21600
            gd x5 */ w 18595 21600
            cxn 3cd4 x4 t
            cxn cd2 l vc
            cxn cd4 x3 y8
            cxn 0 r vc
            rect l y2 x5 y8
            path w=21600 h=21600 stroke=false extrusionOk=false
            M 0 20782
            C 9298 23542 9298 18022 18595 18022
            L 18595 3675
            L 0 3675
            Z
            M 1532 3675
            L 1532 1815
            L 20000 1815
            L 20000 16252
            C 19298 16252 18595 16352 18595 16352
            L 18595 3675
            Z
            M 2972 1815
            L 2972 0
            L 21600 0
            L 21600 14392
            C 20800 14392 20000 14467 20000 14467
            L 20000 1815
            Z
            path w=21600 h=21600 fill=none extrusionOk=false
            M 0 3675
            L 18595 3675
            L 18595 18022
            C 9298 18022 9298 23542 0 20782
            Z
            M 1532 3675
            L 1532 1815
            L 20000 1815
            L 20000 16252
            C 19298 16252 18595 16352 18595 16352
            M 2972 1815
            L 2972 0
            L 21600 0
            L 21600 14392
            C 20800 14392 20000 14467 20000 14467
            path w=21600 h=21600 fill=none stroke=false
            M 0 20782
            C 9298 23542 9298 18022 18595 18022
            L 18595 16352
            C 18595 16352 19298 16252 20000 16252
            L 20000 14467
            C 20000 14467 20800 14392 21600 14392
            L 21600 0
            L 2972 0
            L 2972 1815
            L 1532 1815
            L 1532 3675
            L 0 3675
            Z
            """,
        "flowChartOfflineStorage": """
            gd x4 */ w 3 4
            cxn 0 x4 vc
            cxn cd4 hc b
            cxn cd2 wd4 vc
            cxn 3cd4 hc t
            rect wd4 t x4 vc
            path w=2 h=2 stroke=false extrusionOk=false
            M 0 0
            L 2 0
            L 1 2
            Z
            path w=5 h=5 fill=none extrusionOk=false
            M 2 4
            L 3 4
            path w=2 h=2 fill=none extrusionOk=true
            M 0 0
            L 2 0
            L 1 2
            Z
            """,
        "flowChartOffpageConnector": """
            gd y1 */ h 4 5
            cxn 3cd4 hc t
            cxn cd2 l vc
            cxn cd4 hc b
            cxn 0 r vc
            rect l t r y1
            path w=10 h=10
            M 0 0
            L 10 0
            L 10 8
            L 5 10
            L 0 8
            Z
            """,
        "flowChartOnlineStorage": """
            gd x2 */ w 5 6
            cxn 3cd4 hc t
            cxn cd2 l vc
            cxn cd4 hc b
            cxn 0 x2 vc
            rect wd6 t x2 b
            path w=6 h=6
            M 1 0
            L 6 0
            A 1 3 3cd4 -10800000
            L 1 6
            A 1 3 cd4 cd2
            Z
            """,
        "flowChartOr": """
            gd idx cos wd2 2700000
            gd idy sin hd2 2700000
            gd il +- hc 0 idx
            gd ir +- hc idx 0
            gd it +- vc 0 idy
            gd ib +- vc idy 0
            cxn 3cd4 hc t
            cxn 3cd4 il it
            cxn cd2 l vc
            cxn cd4 il ib
            cxn cd4 hc b
            cxn cd4 ir ib
            cxn 0 r vc
            cxn 3cd4 ir it
            rect il it ir ib
            path stroke=false extrusionOk=false
            M l vc
            A wd2 hd2 cd2 cd4
            A wd2 hd2 3cd4 cd4
            A wd2 hd2 0 cd4
            A wd2 hd2 cd4 cd4
            Z
            path fill=none extrusionOk=false
            M hc t
            L hc b
            M l vc
            L r vc
            path fill=none
            M l vc
            A wd2 hd2 cd2 cd4
            A wd2 hd2 3cd4 cd4
            A wd2 hd2 0 cd4
            A wd2 hd2 cd4 cd4
            Z
            """,
        "flowChartPredefinedProcess": """
            gd x2 */ w 7 8
            cxn 3cd4 hc t
            cxn cd2 l vc
            cxn cd4 hc b
            cxn 0 r vc
            rect wd8 t x2 b
            path w=1 h=1 stroke=false extrusionOk=false
            M 0 0
            L 1 0
            L 1 1
            L 0 1
            Z
            path w=8 h=8 fill=none extrusionOk=false
            M 1 0
            L 1 8
            M 7 0
            L 7 8
            path w=1 h=1 fill=none
            M 0 0
            L 1 0
            L 1 1
            L 0 1
            Z
            """,
        "flowChartPreparation": """
            gd x2 */ w 4 5
            cxn 3cd4 hc t
            cxn cd2 l vc
            cxn cd4 hc b
            cxn 0 r vc
            rect wd5 t x2 b
            path w=10 h=10
            M 0 5
            L 2 0
            L 8 0
            L 10 5
            L 8 10
            L 2 10
            Z
            """,
        "flowChartProcess": """
            cxn 3cd4 hc t
            cxn cd2 l vc
            cxn cd4 hc b
            cxn 0 r vc
            rect l t r b
            path w=1 h=1
            M 0 0
            L 1 0
            L 1 1
            L 0 1
            Z
            """,
        "flowChartPunchedCard": """
            cxn 3cd4 hc t
            cxn cd2 l vc
            cxn cd4 hc b
            cxn 0 r vc
            rect l hd5 r b
            path w=5 h=5
            M 0 1
            L 1 0
            L 5 0
            L 5 5
            L 0 5
            Z
            """,
        "flowChartPunchedTape": """
            gd y2 */ h 9 10
            gd ib */ h 4 5
            cxn 3cd4 hc hd10
            cxn cd2 l vc
            cxn cd4 hc y2
            cxn 0 r vc
            rect l hd5 r ib
            path w=20 h=20
            M 0 2
            A 5 2 cd2 -10800000
            A 5 2 cd2 cd2
            L 20 18
            A 5 2 0 -10800000
            A 5 2 0 cd2
            Z
            """,
        "flowChartSort": """
            gd ir */ w 3 4
            gd ib */ h 3 4
            cxn 3cd4 hc t
            cxn cd2 l vc
            cxn cd4 hc b
            cxn 0 r vc
            rect wd4 hd4 ir ib
            path w=2 h=2 stroke=false extrusionOk=false
            M 0 1
            L 1 0
            L 2 1
            L 1 2
            Z
            path w=2 h=2 fill=none extrusionOk=false
            M 0 1
            L 2 1
            path w=2 h=2 fill=none
            M 0 1
            L 1 0
            L 2 1
            L 1 2
            Z
            """,
        "flowChartSummingJunction": """
            gd idx cos wd2 2700000
            gd idy sin hd2 2700000
            gd il +- hc 0 idx
            gd ir +- hc idx 0
            gd it +- vc 0 idy
            gd ib +- vc idy 0
            cxn 3cd4 hc t
            cxn 3cd4 il it
            cxn cd2 l vc
            cxn cd4 il ib
            cxn cd4 hc b
            cxn cd4 ir ib
            cxn 0 r vc
            cxn 3cd4 ir it
            rect il it ir ib
            path stroke=false extrusionOk=false
            M l vc
            A wd2 hd2 cd2 cd4
            A wd2 hd2 3cd4 cd4
            A wd2 hd2 0 cd4
            A wd2 hd2 cd4 cd4
            Z
            path fill=none extrusionOk=false
            M il it
            L ir ib
            M ir it
            L il ib
            path fill=none
            M l vc
            A wd2 hd2 cd2 cd4
            A wd2 hd2 3cd4 cd4
            A wd2 hd2 0 cd4
            A wd2 hd2 cd4 cd4
            Z
            """,
        "flowChartTerminator": """
            gd il */ w 1018 21600
            gd ir */ w 20582 21600
            gd it */ h 3163 21600
            gd ib */ h 18437 21600
            cxn 3cd4 hc t
            cxn cd2 l vc
            cxn cd4 hc b
            cxn 0 r vc
            rect il it ir ib
            path w=21600 h=21600
            M 3475 0
            L 18125 0
            A 3475 10800 3cd4 cd2
            L 3475 21600
            A 3475 10800 cd4 cd2
            Z
            """,
    ]
}
