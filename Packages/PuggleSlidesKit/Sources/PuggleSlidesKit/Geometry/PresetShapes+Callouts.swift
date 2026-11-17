// DrawingML preset shapes, transcribed from ECMA-376 Part 1's presetShapeDefinitions.xml. See PresetShapeDefinition
// for the statement syntax and the errata fixed.

extension PresetShapeSource {
    static let callouts: [String: String] = [
        "accentBorderCallout1": """
            av adj1 val 18750
            av adj2 val -8333
            av adj3 val 112500
            av adj4 val -38333
            gd y1 */ h adj1 100000
            gd x1 */ w adj2 100000
            gd y2 */ h adj3 100000
            gd x2 */ w adj4 100000
            ahXY gdRefX=adj2 minX=-2147483647 maxX=2147483647 gdRefY=adj1 minY=-2147483647 maxY=2147483647 x=x1 y=y1
            ahXY gdRefX=adj4 minX=-2147483647 maxX=2147483647 gdRefY=adj3 minY=-2147483647 maxY=2147483647 x=x2 y=y2
            cxn 0 r vc
            cxn cd4 hc b
            cxn cd2 l vc
            cxn 3cd4 hc t
            rect l t r b
            path extrusionOk=false
            M l t
            L r t
            L r b
            L l b
            Z
            path fill=none extrusionOk=false
            M x1 t
            Z
            L x1 b
            path fill=none extrusionOk=false
            M x1 y1
            L x2 y2
            """,
        "accentBorderCallout2": """
            av adj1 val 18750
            av adj2 val -8333
            av adj3 val 18750
            av adj4 val -16667
            av adj5 val 112500
            av adj6 val -46667
            gd y1 */ h adj1 100000
            gd x1 */ w adj2 100000
            gd y2 */ h adj3 100000
            gd x2 */ w adj4 100000
            gd y3 */ h adj5 100000
            gd x3 */ w adj6 100000
            ahXY gdRefX=adj2 minX=-2147483647 maxX=2147483647 gdRefY=adj1 minY=-2147483647 maxY=2147483647 x=x1 y=y1
            ahXY gdRefX=adj4 minX=-2147483647 maxX=2147483647 gdRefY=adj3 minY=-2147483647 maxY=2147483647 x=x2 y=y2
            ahXY gdRefX=adj6 minX=-2147483647 maxX=2147483647 gdRefY=adj5 minY=-2147483647 maxY=2147483647 x=x3 y=y3
            cxn 0 r vc
            cxn cd4 hc b
            cxn cd2 l vc
            cxn 3cd4 hc t
            rect l t r b
            path extrusionOk=false
            M l t
            L r t
            L r b
            L l b
            Z
            path fill=none extrusionOk=false
            M x1 t
            Z
            L x1 b
            path fill=none extrusionOk=false
            M x1 y1
            L x2 y2
            L x3 y3
            """,
        "accentBorderCallout3": """
            av adj1 val 18750
            av adj2 val -8333
            av adj3 val 18750
            av adj4 val -16667
            av adj5 val 100000
            av adj6 val -16667
            av adj7 val 112963
            av adj8 val -8333
            gd y1 */ h adj1 100000
            gd x1 */ w adj2 100000
            gd y2 */ h adj3 100000
            gd x2 */ w adj4 100000
            gd y3 */ h adj5 100000
            gd x3 */ w adj6 100000
            gd y4 */ h adj7 100000
            gd x4 */ w adj8 100000
            ahXY gdRefX=adj2 minX=-2147483647 maxX=2147483647 gdRefY=adj1 minY=-2147483647 maxY=2147483647 x=x1 y=y1
            ahXY gdRefX=adj4 minX=-2147483647 maxX=2147483647 gdRefY=adj3 minY=-2147483647 maxY=2147483647 x=x2 y=y2
            ahXY gdRefX=adj6 minX=-2147483647 maxX=2147483647 gdRefY=adj5 minY=-2147483647 maxY=2147483647 x=x3 y=y3
            ahXY gdRefX=adj8 minX=-2147483647 maxX=2147483647 gdRefY=adj7 minY=-2147483647 maxY=2147483647 x=x4 y=y4
            cxn 0 r vc
            cxn cd4 hc b
            cxn cd2 l vc
            cxn 3cd4 hc t
            rect l t r b
            path extrusionOk=false
            M l t
            L r t
            L r b
            L l b
            Z
            path fill=none extrusionOk=false
            M x1 t
            Z
            L x1 b
            path fill=none extrusionOk=false
            M x1 y1
            L x2 y2
            L x3 y3
            L x4 y4
            """,
        "accentCallout1": """
            av adj1 val 18750
            av adj2 val -8333
            av adj3 val 112500
            av adj4 val -38333
            gd y1 */ h adj1 100000
            gd x1 */ w adj2 100000
            gd y2 */ h adj3 100000
            gd x2 */ w adj4 100000
            ahXY gdRefX=adj2 minX=-2147483647 maxX=2147483647 gdRefY=adj1 minY=-2147483647 maxY=2147483647 x=x1 y=y1
            ahXY gdRefX=adj4 minX=-2147483647 maxX=2147483647 gdRefY=adj3 minY=-2147483647 maxY=2147483647 x=x2 y=y2
            cxn 0 r vc
            cxn cd4 hc b
            cxn cd2 l vc
            cxn 3cd4 hc t
            rect l t r b
            path stroke=false extrusionOk=false
            M l t
            L r t
            L r b
            L l b
            Z
            path fill=none extrusionOk=false
            M x1 t
            Z
            L x1 b
            path fill=none extrusionOk=false
            M x1 y1
            L x2 y2
            """,
        "accentCallout2": """
            av adj1 val 18750
            av adj2 val -8333
            av adj3 val 18750
            av adj4 val -16667
            av adj5 val 112500
            av adj6 val -46667
            gd y1 */ h adj1 100000
            gd x1 */ w adj2 100000
            gd y2 */ h adj3 100000
            gd x2 */ w adj4 100000
            gd y3 */ h adj5 100000
            gd x3 */ w adj6 100000
            ahXY gdRefX=adj2 minX=-2147483647 maxX=2147483647 gdRefY=adj1 minY=-2147483647 maxY=2147483647 x=x1 y=y1
            ahXY gdRefX=adj4 minX=-2147483647 maxX=2147483647 gdRefY=adj3 minY=-2147483647 maxY=2147483647 x=x2 y=y2
            ahXY gdRefX=adj6 minX=-2147483647 maxX=2147483647 gdRefY=adj5 minY=-2147483647 maxY=2147483647 x=x3 y=y3
            cxn 0 r vc
            cxn cd4 hc b
            cxn cd2 l vc
            cxn 3cd4 hc t
            rect l t r b
            path stroke=false extrusionOk=false
            M l t
            L r t
            L r b
            L l b
            Z
            path fill=none extrusionOk=false
            M x1 t
            Z
            L x1 b
            path fill=none extrusionOk=false
            M x1 y1
            L x2 y2
            L x3 y3
            """,
        "accentCallout3": """
            av adj1 val 18750
            av adj2 val -8333
            av adj3 val 18750
            av adj4 val -16667
            av adj5 val 100000
            av adj6 val -16667
            av adj7 val 112963
            av adj8 val -8333
            gd y1 */ h adj1 100000
            gd x1 */ w adj2 100000
            gd y2 */ h adj3 100000
            gd x2 */ w adj4 100000
            gd y3 */ h adj5 100000
            gd x3 */ w adj6 100000
            gd y4 */ h adj7 100000
            gd x4 */ w adj8 100000
            ahXY gdRefX=adj2 minX=-2147483647 maxX=2147483647 gdRefY=adj1 minY=-2147483647 maxY=2147483647 x=x1 y=y1
            ahXY gdRefX=adj4 minX=-2147483647 maxX=2147483647 gdRefY=adj3 minY=-2147483647 maxY=2147483647 x=x2 y=y2
            ahXY gdRefX=adj6 minX=-2147483647 maxX=2147483647 gdRefY=adj5 minY=-2147483647 maxY=2147483647 x=x3 y=y3
            ahXY gdRefX=adj8 minX=-2147483647 maxX=2147483647 gdRefY=adj7 minY=-2147483647 maxY=2147483647 x=x4 y=y4
            cxn 0 r vc
            cxn cd4 hc b
            cxn cd2 l vc
            cxn 3cd4 hc t
            rect l t r b
            path stroke=false extrusionOk=false
            M l t
            L r t
            L r b
            L l b
            Z
            path fill=none extrusionOk=false
            M x1 t
            Z
            L x1 b
            path fill=none extrusionOk=false
            M x1 y1
            L x2 y2
            L x3 y3
            L x4 y4
            """,
        "borderCallout1": """
            av adj1 val 18750
            av adj2 val -8333
            av adj3 val 112500
            av adj4 val -38333
            gd y1 */ h adj1 100000
            gd x1 */ w adj2 100000
            gd y2 */ h adj3 100000
            gd x2 */ w adj4 100000
            ahXY gdRefX=adj2 minX=-2147483647 maxX=2147483647 gdRefY=adj1 minY=-2147483647 maxY=2147483647 x=x1 y=y1
            ahXY gdRefX=adj4 minX=-2147483647 maxX=2147483647 gdRefY=adj3 minY=-2147483647 maxY=2147483647 x=x2 y=y2
            cxn 0 r vc
            cxn cd4 hc b
            cxn cd2 l vc
            cxn 3cd4 hc t
            rect l t r b
            path extrusionOk=false
            M l t
            L r t
            L r b
            L l b
            Z
            path fill=none extrusionOk=false
            M x1 y1
            L x2 y2
            """,
        "borderCallout2": """
            av adj1 val 18750
            av adj2 val -8333
            av adj3 val 18750
            av adj4 val -16667
            av adj5 val 112500
            av adj6 val -46667
            gd y1 */ h adj1 100000
            gd x1 */ w adj2 100000
            gd y2 */ h adj3 100000
            gd x2 */ w adj4 100000
            gd y3 */ h adj5 100000
            gd x3 */ w adj6 100000
            ahXY gdRefX=adj2 minX=-2147483647 maxX=2147483647 gdRefY=adj1 minY=-2147483647 maxY=2147483647 x=x1 y=y1
            ahXY gdRefX=adj4 minX=-2147483647 maxX=2147483647 gdRefY=adj3 minY=-2147483647 maxY=2147483647 x=x2 y=y2
            ahXY gdRefX=adj6 minX=-2147483647 maxX=2147483647 gdRefY=adj5 minY=-2147483647 maxY=2147483647 x=x3 y=y3
            cxn 0 r vc
            cxn cd4 hc b
            cxn cd2 l vc
            cxn 3cd4 hc t
            rect l t r b
            path extrusionOk=false
            M l t
            L r t
            L r b
            L l b
            Z
            path fill=none extrusionOk=false
            M x1 y1
            L x2 y2
            L x3 y3
            """,
        "borderCallout3": """
            av adj1 val 18750
            av adj2 val -8333
            av adj3 val 18750
            av adj4 val -16667
            av adj5 val 100000
            av adj6 val -16667
            av adj7 val 112963
            av adj8 val -8333
            gd y1 */ h adj1 100000
            gd x1 */ w adj2 100000
            gd y2 */ h adj3 100000
            gd x2 */ w adj4 100000
            gd y3 */ h adj5 100000
            gd x3 */ w adj6 100000
            gd y4 */ h adj7 100000
            gd x4 */ w adj8 100000
            ahXY gdRefX=adj2 minX=-2147483647 maxX=2147483647 gdRefY=adj1 minY=-2147483647 maxY=2147483647 x=x1 y=y1
            ahXY gdRefX=adj4 minX=-2147483647 maxX=2147483647 gdRefY=adj3 minY=-2147483647 maxY=2147483647 x=x2 y=y2
            ahXY gdRefX=adj6 minX=-2147483647 maxX=2147483647 gdRefY=adj5 minY=-2147483647 maxY=2147483647 x=x3 y=y3
            ahXY gdRefX=adj8 minX=-2147483647 maxX=2147483647 gdRefY=adj7 minY=-2147483647 maxY=2147483647 x=x4 y=y4
            cxn 0 r vc
            cxn cd4 hc b
            cxn cd2 l vc
            cxn 3cd4 hc t
            rect l t r b
            path extrusionOk=false
            M l t
            L r t
            L r b
            L l b
            Z
            path fill=none extrusionOk=false
            M x1 y1
            L x2 y2
            L x3 y3
            L x4 y4
            """,
        "callout1": """
            av adj1 val 18750
            av adj2 val -8333
            av adj3 val 112500
            av adj4 val -38333
            gd y1 */ h adj1 100000
            gd x1 */ w adj2 100000
            gd y2 */ h adj3 100000
            gd x2 */ w adj4 100000
            ahXY gdRefX=adj2 minX=-2147483647 maxX=2147483647 gdRefY=adj1 minY=-2147483647 maxY=2147483647 x=x1 y=y1
            ahXY gdRefX=adj4 minX=-2147483647 maxX=2147483647 gdRefY=adj3 minY=-2147483647 maxY=2147483647 x=x2 y=y2
            cxn 0 r vc
            cxn cd4 hc b
            cxn cd2 l vc
            cxn 3cd4 hc t
            rect l t r b
            path stroke=false extrusionOk=false
            M l t
            L r t
            L r b
            L l b
            Z
            path fill=none extrusionOk=false
            M x1 y1
            L x2 y2
            """,
        "callout2": """
            av adj1 val 18750
            av adj2 val -8333
            av adj3 val 18750
            av adj4 val -16667
            av adj5 val 112500
            av adj6 val -46667
            gd y1 */ h adj1 100000
            gd x1 */ w adj2 100000
            gd y2 */ h adj3 100000
            gd x2 */ w adj4 100000
            gd y3 */ h adj5 100000
            gd x3 */ w adj6 100000
            ahXY gdRefX=adj2 minX=-2147483647 maxX=2147483647 gdRefY=adj1 minY=-2147483647 maxY=2147483647 x=x1 y=y1
            ahXY gdRefX=adj4 minX=-2147483647 maxX=2147483647 gdRefY=adj3 minY=-2147483647 maxY=2147483647 x=x2 y=y2
            ahXY gdRefX=adj6 minX=-2147483647 maxX=2147483647 gdRefY=adj5 minY=-2147483647 maxY=2147483647 x=x3 y=y3
            cxn 0 r vc
            cxn cd4 hc b
            cxn cd2 l vc
            cxn 3cd4 hc t
            rect l t r b
            path stroke=false extrusionOk=false
            M l t
            L r t
            L r b
            L l b
            Z
            path fill=none extrusionOk=false
            M x1 y1
            L x2 y2
            L x3 y3
            """,
        "callout3": """
            av adj1 val 18750
            av adj2 val -8333
            av adj3 val 18750
            av adj4 val -16667
            av adj5 val 100000
            av adj6 val -16667
            av adj7 val 112963
            av adj8 val -8333
            gd y1 */ h adj1 100000
            gd x1 */ w adj2 100000
            gd y2 */ h adj3 100000
            gd x2 */ w adj4 100000
            gd y3 */ h adj5 100000
            gd x3 */ w adj6 100000
            gd y4 */ h adj7 100000
            gd x4 */ w adj8 100000
            ahXY gdRefX=adj2 minX=-2147483647 maxX=2147483647 gdRefY=adj1 minY=-2147483647 maxY=2147483647 x=x1 y=y1
            ahXY gdRefX=adj4 minX=-2147483647 maxX=2147483647 gdRefY=adj3 minY=-2147483647 maxY=2147483647 x=x2 y=y2
            ahXY gdRefX=adj6 minX=-2147483647 maxX=2147483647 gdRefY=adj5 minY=-2147483647 maxY=2147483647 x=x3 y=y3
            ahXY gdRefX=adj8 minX=-2147483647 maxX=2147483647 gdRefY=adj7 minY=-2147483647 maxY=2147483647 x=x4 y=y4
            cxn 0 r vc
            cxn cd4 hc b
            cxn cd2 l vc
            cxn 3cd4 hc t
            rect l t r b
            path stroke=false extrusionOk=false
            M l t
            L r t
            L r b
            L l b
            Z
            path fill=none extrusionOk=false
            M x1 y1
            L x2 y2
            L x3 y3
            L x4 y4
            """,
        "cloudCallout": """
            av adj1 val -20833
            av adj2 val 62500
            gd dxPos */ w adj1 100000
            gd dyPos */ h adj2 100000
            gd xPos +- hc dxPos 0
            gd yPos +- vc dyPos 0
            gd ht cat2 hd2 dxPos dyPos
            gd wt sat2 wd2 dxPos dyPos
            gd g2 cat2 wd2 ht wt
            gd g3 sat2 hd2 ht wt
            gd g4 +- hc g2 0
            gd g5 +- vc g3 0
            gd g6 +- g4 0 xPos
            gd g7 +- g5 0 yPos
            gd g8 mod g6 g7 0
            gd g9 */ ss 6600 21600
            gd g10 +- g8 0 g9
            gd g11 */ g10 1 3
            gd g12 */ ss 1800 21600
            gd g13 +- g11 g12 0
            gd g14 */ g13 g6 g8
            gd g15 */ g13 g7 g8
            gd g16 +- g14 xPos 0
            gd g17 +- g15 yPos 0
            gd g18 */ ss 4800 21600
            gd g19 */ g11 2 1
            gd g20 +- g18 g19 0
            gd g21 */ g20 g6 g8
            gd g22 */ g20 g7 g8
            gd g23 +- g21 xPos 0
            gd g24 +- g22 yPos 0
            gd g25 */ ss 1200 21600
            gd g26 */ ss 600 21600
            gd x23 +- xPos g26 0
            gd x24 +- g16 g25 0
            gd x25 +- g23 g12 0
            gd il */ w 2977 21600
            gd it */ h 3262 21600
            gd ir */ w 17087 21600
            gd ib */ h 17337 21600
            gd g27 */ w 67 21600
            gd g28 */ h 21577 21600
            gd g29 */ w 21582 21600
            gd g30 */ h 1235 21600
            gd pang at2 dxPos dyPos
            ahXY gdRefX=adj1 minX=-2147483647 maxX=2147483647 gdRefY=adj2 minY=-2147483647 maxY=2147483647 x=xPos y=yPos
            cxn cd2 g27 vc
            cxn cd4 hc g28
            cxn 0 g29 vc
            cxn 3cd4 hc g30
            cxn pang xPos yPos
            rect il it ir ib
            path w=43200 h=43200
            M 3900 14370
            A 6753 9190 -11429249 7426832
            A 5333 7267 -8646143 5396714
            A 4365 5945 -8748475 5983381
            A 4857 6595 -7859164 7034504
            A 5333 7273 -4722533 6541615
            A 6775 9220 -2776035 7816140
            A 5785 7867 37501 6842000
            A 6752 9215 1347096 6910353
            A 7720 10543 3974558 4542661
            A 4360 5918 -16496525 8804134
            A 4345 5945 -14809710 9151131
            Z
            path
            M x23 yPos
            A g26 g26 0 21600000
            Z
            path
            M x24 g17
            A g25 g25 0 21600000
            Z
            path
            M x25 g24
            A g12 g12 0 21600000
            Z
            path w=43200 h=43200 fill=none extrusionOk=false
            M 4693 26177
            A 4345 5945 5204520 1585770
            M 6928 34899
            A 4360 5918 4416628 686848
            M 16478 39090
            A 6752 9215 8257449 844866
            M 28827 34751
            A 6752 9215 387196 959901
            M 34129 22954
            A 5785 7867 -4217541 4255042
            M 41798 15354
            A 5333 7273 1819082 1665090
            M 38324 5426
            A 4857 6595 -824660 891534
            M 29078 3952
            A 4857 6595 -8950887 1091722
            M 22141 4720
            A 4365 5945 -9809656 1061181
            M 14000 5192
            A 6753 9190 -4002417 739161
            M 4127 15789
            A 6753 9190 9459261 711490
            """,
        "downArrowCallout": """
            av adj1 val 25000
            av adj2 val 25000
            av adj3 val 25000
            av adj4 val 64977
            gd maxAdj2 */ 50000 w ss
            gd a2 pin 0 adj2 maxAdj2
            gd maxAdj1 */ a2 2 1
            gd a1 pin 0 adj1 maxAdj1
            gd maxAdj3 */ 100000 h ss
            gd a3 pin 0 adj3 maxAdj3
            gd q2 */ a3 ss h
            gd maxAdj4 +- 100000 0 q2
            gd a4 pin 0 adj4 maxAdj4
            gd dx1 */ ss a2 100000
            gd dx2 */ ss a1 200000
            gd x1 +- hc 0 dx1
            gd x2 +- hc 0 dx2
            gd x3 +- hc dx2 0
            gd x4 +- hc dx1 0
            gd dy3 */ ss a3 100000
            gd y3 +- b 0 dy3
            gd y2 */ h a4 100000
            gd y1 */ y2 1 2
            ahXY gdRefX=adj1 minX=0 maxX=maxAdj1 x=x2 y=y3
            ahXY gdRefX=adj2 minX=0 maxX=maxAdj2 x=x1 y=b
            ahXY gdRefY=adj3 minY=0 maxY=maxAdj3 x=r y=y3
            ahXY gdRefY=adj4 minY=0 maxY=maxAdj4 x=l y=y2
            cxn 3cd4 hc t
            cxn cd2 l y1
            cxn cd4 hc b
            cxn 0 r y1
            rect l t r y2
            path
            M l t
            L r t
            L r y2
            L x3 y2
            L x3 y3
            L x4 y3
            L hc b
            L x1 y3
            L x2 y3
            L x2 y2
            L l y2
            Z
            """,
        "leftArrowCallout": """
            av adj1 val 25000
            av adj2 val 25000
            av adj3 val 25000
            av adj4 val 64977
            gd maxAdj2 */ 50000 h ss
            gd a2 pin 0 adj2 maxAdj2
            gd maxAdj1 */ a2 2 1
            gd a1 pin 0 adj1 maxAdj1
            gd maxAdj3 */ 100000 w ss
            gd a3 pin 0 adj3 maxAdj3
            gd q2 */ a3 ss w
            gd maxAdj4 +- 100000 0 q2
            gd a4 pin 0 adj4 maxAdj4
            gd dy1 */ ss a2 100000
            gd dy2 */ ss a1 200000
            gd y1 +- vc 0 dy1
            gd y2 +- vc 0 dy2
            gd y3 +- vc dy2 0
            gd y4 +- vc dy1 0
            gd x1 */ ss a3 100000
            gd dx2 */ w a4 100000
            gd x2 +- r 0 dx2
            gd x3 +/ x2 r 2
            ahXY gdRefY=adj1 minY=0 maxY=maxAdj1 x=x1 y=y2
            ahXY gdRefY=adj2 minY=0 maxY=maxAdj2 x=l y=y1
            ahXY gdRefX=adj3 minX=0 maxX=maxAdj3 x=x1 y=t
            ahXY gdRefX=adj4 minX=0 maxX=maxAdj4 x=x2 y=b
            cxn 3cd4 x3 t
            cxn cd2 l vc
            cxn cd4 x3 b
            cxn 0 r vc
            rect x2 t r b
            path
            M l vc
            L x1 y1
            L x1 y2
            L x2 y2
            L x2 t
            L r t
            L r b
            L x2 b
            L x2 y3
            L x1 y3
            L x1 y4
            Z
            """,
        "leftRightArrowCallout": """
            av adj1 val 25000
            av adj2 val 25000
            av adj3 val 25000
            av adj4 val 48123
            gd maxAdj2 */ 50000 h ss
            gd a2 pin 0 adj2 maxAdj2
            gd maxAdj1 */ a2 2 1
            gd a1 pin 0 adj1 maxAdj1
            gd maxAdj3 */ 50000 w ss
            gd a3 pin 0 adj3 maxAdj3
            gd q2 */ a3 ss wd2
            gd maxAdj4 +- 100000 0 q2
            gd a4 pin 0 adj4 maxAdj4
            gd dy1 */ ss a2 100000
            gd dy2 */ ss a1 200000
            gd y1 +- vc 0 dy1
            gd y2 +- vc 0 dy2
            gd y3 +- vc dy2 0
            gd y4 +- vc dy1 0
            gd x1 */ ss a3 100000
            gd x4 +- r 0 x1
            gd dx2 */ w a4 200000
            gd x2 +- hc 0 dx2
            gd x3 +- hc dx2 0
            ahXY gdRefY=adj1 minY=0 maxY=maxAdj1 x=x1 y=y2
            ahXY gdRefY=adj2 minY=0 maxY=maxAdj2 x=l y=y1
            ahXY gdRefX=adj3 minX=0 maxX=maxAdj3 x=x1 y=t
            ahXY gdRefX=adj4 minX=0 maxX=maxAdj4 x=x2 y=b
            cxn 3cd4 hc t
            cxn cd2 l vc
            cxn cd4 hc b
            cxn 0 r vc
            rect x2 t x3 b
            path
            M l vc
            L x1 y1
            L x1 y2
            L x2 y2
            L x2 t
            L x3 t
            L x3 y2
            L x4 y2
            L x4 y1
            L r vc
            L x4 y4
            L x4 y3
            L x3 y3
            L x3 b
            L x2 b
            L x2 y3
            L x1 y3
            L x1 y4
            Z
            """,
        "quadArrowCallout": """
            av adj1 val 18515
            av adj2 val 18515
            av adj3 val 18515
            av adj4 val 48123
            gd a2 pin 0 adj2 50000
            gd maxAdj1 */ a2 2 1
            gd a1 pin 0 adj1 maxAdj1
            gd maxAdj3 +- 50000 0 a2
            gd a3 pin 0 adj3 maxAdj3
            gd q2 */ a3 2 1
            gd maxAdj4 +- 100000 0 q2
            gd a4 pin a1 adj4 maxAdj4
            gd dx2 */ ss a2 100000
            gd dx3 */ ss a1 200000
            gd ah */ ss a3 100000
            gd dx1 */ w a4 200000
            gd dy1 */ h a4 200000
            gd x8 +- r 0 ah
            gd x2 +- hc 0 dx1
            gd x7 +- hc dx1 0
            gd x3 +- hc 0 dx2
            gd x6 +- hc dx2 0
            gd x4 +- hc 0 dx3
            gd x5 +- hc dx3 0
            gd y8 +- b 0 ah
            gd y2 +- vc 0 dy1
            gd y7 +- vc dy1 0
            gd y3 +- vc 0 dx2
            gd y6 +- vc dx2 0
            gd y4 +- vc 0 dx3
            gd y5 +- vc dx3 0
            ahXY gdRefX=adj1 minX=0 maxX=maxAdj1 x=x4 y=ah
            ahXY gdRefX=adj2 minX=0 maxX=50000 x=x3 y=t
            ahXY gdRefY=adj3 minY=0 maxY=maxAdj3 x=r y=ah
            ahXY gdRefY=adj4 minY=a1 maxY=maxAdj4 x=l y=y2
            cxn 3cd4 hc t
            cxn cd2 l vc
            cxn cd4 hc b
            cxn 0 r vc
            rect x2 y2 x7 y7
            path
            M l vc
            L ah y3
            L ah y4
            L x2 y4
            L x2 y2
            L x4 y2
            L x4 ah
            L x3 ah
            L hc t
            L x6 ah
            L x5 ah
            L x5 y2
            L x7 y2
            L x7 y4
            L x8 y4
            L x8 y3
            L r vc
            L x8 y6
            L x8 y5
            L x7 y5
            L x7 y7
            L x5 y7
            L x5 y8
            L x6 y8
            L hc b
            L x3 y8
            L x4 y8
            L x4 y7
            L x2 y7
            L x2 y5
            L ah y5
            L ah y6
            Z
            """,
        "rightArrowCallout": """
            av adj1 val 25000
            av adj2 val 25000
            av adj3 val 25000
            av adj4 val 64977
            gd maxAdj2 */ 50000 h ss
            gd a2 pin 0 adj2 maxAdj2
            gd maxAdj1 */ a2 2 1
            gd a1 pin 0 adj1 maxAdj1
            gd maxAdj3 */ 100000 w ss
            gd a3 pin 0 adj3 maxAdj3
            gd q2 */ a3 ss w
            gd maxAdj4 +- 100000 0 q2
            gd a4 pin 0 adj4 maxAdj4
            gd dy1 */ ss a2 100000
            gd dy2 */ ss a1 200000
            gd y1 +- vc 0 dy1
            gd y2 +- vc 0 dy2
            gd y3 +- vc dy2 0
            gd y4 +- vc dy1 0
            gd dx3 */ ss a3 100000
            gd x3 +- r 0 dx3
            gd x2 */ w a4 100000
            gd x1 */ x2 1 2
            ahXY gdRefY=adj1 minY=0 maxY=maxAdj1 x=x3 y=y2
            ahXY gdRefY=adj2 minY=0 maxY=maxAdj2 x=r y=y1
            ahXY gdRefX=adj3 minX=0 maxX=maxAdj3 x=x3 y=t
            ahXY gdRefX=adj4 minX=0 maxX=maxAdj4 x=x2 y=b
            cxn 3cd4 x1 t
            cxn cd2 l vc
            cxn cd4 x1 b
            cxn 0 r vc
            rect l t x2 b
            path
            M l t
            L x2 t
            L x2 y2
            L x3 y2
            L x3 y1
            L r vc
            L x3 y4
            L x3 y3
            L x2 y3
            L x2 b
            L l b
            Z
            """,
        "upArrowCallout": """
            av adj1 val 25000
            av adj2 val 25000
            av adj3 val 25000
            av adj4 val 64977
            gd maxAdj2 */ 50000 w ss
            gd a2 pin 0 adj2 maxAdj2
            gd maxAdj1 */ a2 2 1
            gd a1 pin 0 adj1 maxAdj1
            gd maxAdj3 */ 100000 h ss
            gd a3 pin 0 adj3 maxAdj3
            gd q2 */ a3 ss h
            gd maxAdj4 +- 100000 0 q2
            gd a4 pin 0 adj4 maxAdj4
            gd dx1 */ ss a2 100000
            gd dx2 */ ss a1 200000
            gd x1 +- hc 0 dx1
            gd x2 +- hc 0 dx2
            gd x3 +- hc dx2 0
            gd x4 +- hc dx1 0
            gd y1 */ ss a3 100000
            gd dy2 */ h a4 100000
            gd y2 +- b 0 dy2
            gd y3 +/ y2 b 2
            ahXY gdRefX=adj1 minX=0 maxX=maxAdj1 x=x2 y=y1
            ahXY gdRefX=adj2 minX=0 maxX=maxAdj2 x=x1 y=t
            ahXY gdRefY=adj3 minY=0 maxY=maxAdj3 x=r y=y1
            ahXY gdRefY=adj4 minY=0 maxY=maxAdj4 x=l y=y2
            cxn 3cd4 hc t
            cxn cd2 l y2
            cxn cd4 hc b
            cxn 0 r y2
            rect l y2 r b
            path
            M l y2
            L x2 y2
            L x2 y1
            L x1 y1
            L hc t
            L x4 y1
            L x3 y1
            L x3 y2
            L r y2
            L r b
            L l b
            Z
            """,
        "upDownArrowCallout": """
            av adj1 val 25000
            av adj2 val 25000
            av adj3 val 25000
            av adj4 val 48123
            gd maxAdj2 */ 50000 w ss
            gd a2 pin 0 adj2 maxAdj2
            gd maxAdj1 */ a2 2 1
            gd a1 pin 0 adj1 maxAdj1
            gd maxAdj3 */ 50000 h ss
            gd a3 pin 0 adj3 maxAdj3
            gd q2 */ a3 ss hd2
            gd maxAdj4 +- 100000 0 q2
            gd a4 pin 0 adj4 maxAdj4
            gd dx1 */ ss a2 100000
            gd dx2 */ ss a1 200000
            gd x1 +- hc 0 dx1
            gd x2 +- hc 0 dx2
            gd x3 +- hc dx2 0
            gd x4 +- hc dx1 0
            gd y1 */ ss a3 100000
            gd y4 +- b 0 y1
            gd dy2 */ h a4 200000
            gd y2 +- vc 0 dy2
            gd y3 +- vc dy2 0
            ahXY gdRefX=adj1 minX=0 maxX=maxAdj1 x=x2 y=y1
            ahXY gdRefX=adj2 minX=0 maxX=maxAdj2 x=x1 y=t
            ahXY gdRefY=adj3 minY=0 maxY=maxAdj3 x=r y=y1
            ahXY gdRefY=adj4 minY=0 maxY=maxAdj4 x=l y=y2
            cxn 3cd4 hc t
            cxn cd2 l vc
            cxn cd4 hc b
            cxn 0 r vc
            rect l y2 r y3
            path
            M l y2
            L x2 y2
            L x2 y1
            L x1 y1
            L hc t
            L x4 y1
            L x3 y1
            L x3 y2
            L r y2
            L r y3
            L x3 y3
            L x3 y4
            L x4 y4
            L hc b
            L x1 y4
            L x2 y4
            L x2 y3
            L l y3
            Z
            """,
        "wedgeEllipseCallout": """
            av adj1 val -20833
            av adj2 val 62500
            gd dxPos */ w adj1 100000
            gd dyPos */ h adj2 100000
            gd xPos +- hc dxPos 0
            gd yPos +- vc dyPos 0
            gd sdx */ dxPos h 1
            gd sdy */ dyPos w 1
            gd pang at2 sdx sdy
            gd stAng +- pang 660000 0
            gd enAng +- pang 0 660000
            gd dx1 cos wd2 stAng
            gd dy1 sin hd2 stAng
            gd x1 +- hc dx1 0
            gd y1 +- vc dy1 0
            gd dx2 cos wd2 enAng
            gd dy2 sin hd2 enAng
            gd x2 +- hc dx2 0
            gd y2 +- vc dy2 0
            gd stAng1 at2 dx1 dy1
            gd enAng1 at2 dx2 dy2
            gd swAng1 +- enAng1 0 stAng1
            gd swAng2 +- swAng1 21600000 0
            gd swAng ?: swAng1 swAng1 swAng2
            gd idx cos wd2 2700000
            gd idy sin hd2 2700000
            gd il +- hc 0 idx
            gd ir +- hc idx 0
            gd it +- vc 0 idy
            gd ib +- vc idy 0
            ahXY gdRefX=adj1 minX=-2147483647 maxX=2147483647 gdRefY=adj2 minY=-2147483647 maxY=2147483647 x=xPos y=yPos
            cxn 3cd4 hc t
            cxn 3cd4 il it
            cxn cd4 il ib
            cxn cd4 hc b
            cxn cd4 ir ib
            cxn 0 r vc
            cxn 3cd4 ir it
            cxn pang xPos yPos
            rect il it ir ib
            path
            M xPos yPos
            L x1 y1
            A wd2 hd2 stAng1 swAng
            Z
            """,
        "wedgeRectCallout": """
            av adj1 val -20833
            av adj2 val 62500
            gd dxPos */ w adj1 100000
            gd dyPos */ h adj2 100000
            gd xPos +- hc dxPos 0
            gd yPos +- vc dyPos 0
            gd dx +- xPos 0 hc
            gd dy +- yPos 0 vc
            gd dq */ dxPos h w
            gd ady abs dyPos
            gd adq abs dq
            gd dz +- ady 0 adq
            gd xg1 ?: dxPos 7 2
            gd xg2 ?: dxPos 10 5
            gd x1 */ w xg1 12
            gd x2 */ w xg2 12
            gd yg1 ?: dyPos 7 2
            gd yg2 ?: dyPos 10 5
            gd y1 */ h yg1 12
            gd y2 */ h yg2 12
            gd t1 ?: dxPos l xPos
            gd xl ?: dz l t1
            gd t2 ?: dyPos x1 xPos
            gd xt ?: dz t2 x1
            gd t3 ?: dxPos xPos r
            gd xr ?: dz r t3
            gd t4 ?: dyPos xPos x1
            gd xb ?: dz t4 x1
            gd t5 ?: dxPos y1 yPos
            gd yl ?: dz y1 t5
            gd t6 ?: dyPos t yPos
            gd yt ?: dz t6 t
            gd t7 ?: dxPos yPos y1
            gd yr ?: dz y1 t7
            gd t8 ?: dyPos yPos b
            gd yb ?: dz t8 b
            ahXY gdRefX=adj1 minX=-2147483647 maxX=2147483647 gdRefY=adj2 minY=-2147483647 maxY=2147483647 x=xPos y=yPos
            cxn 3cd4 hc t
            cxn cd2 l vc
            cxn cd4 hc b
            cxn 0 r vc
            cxn cd4 xPos yPos
            rect l t r b
            path
            M l t
            L x1 t
            L xt yt
            L x2 t
            L r t
            L r y1
            L xr yr
            L r y2
            L r b
            L x2 b
            L xb yb
            L x1 b
            L l b
            L l y2
            L xl yl
            L l y1
            Z
            """,
        "wedgeRoundRectCallout": """
            av adj1 val -20833
            av adj2 val 62500
            av adj3 val 16667
            gd dxPos */ w adj1 100000
            gd dyPos */ h adj2 100000
            gd xPos +- hc dxPos 0
            gd yPos +- vc dyPos 0
            gd dq */ dxPos h w
            gd ady abs dyPos
            gd adq abs dq
            gd dz +- ady 0 adq
            gd xg1 ?: dxPos 7 2
            gd xg2 ?: dxPos 10 5
            gd x1 */ w xg1 12
            gd x2 */ w xg2 12
            gd yg1 ?: dyPos 7 2
            gd yg2 ?: dyPos 10 5
            gd y1 */ h yg1 12
            gd y2 */ h yg2 12
            gd t1 ?: dxPos l xPos
            gd xl ?: dz l t1
            gd t2 ?: dyPos x1 xPos
            gd xt ?: dz t2 x1
            gd t3 ?: dxPos xPos r
            gd xr ?: dz r t3
            gd t4 ?: dyPos xPos x1
            gd xb ?: dz t4 x1
            gd t5 ?: dxPos y1 yPos
            gd yl ?: dz y1 t5
            gd t6 ?: dyPos t yPos
            gd yt ?: dz t6 t
            gd t7 ?: dxPos yPos y1
            gd yr ?: dz y1 t7
            gd t8 ?: dyPos yPos b
            gd yb ?: dz t8 b
            gd u1 */ ss adj3 100000
            gd u2 +- r 0 u1
            gd v2 +- b 0 u1
            gd il */ u1 29289 100000
            gd ir +- r 0 il
            gd ib +- b 0 il
            ahXY gdRefX=adj1 minX=-2147483647 maxX=2147483647 gdRefY=adj2 minY=-2147483647 maxY=2147483647 x=xPos y=yPos
            cxn 3cd4 hc t
            cxn cd2 l vc
            cxn cd4 hc b
            cxn 0 r vc
            cxn cd4 xPos yPos
            rect il il ir ib
            path
            M l u1
            A u1 u1 cd2 cd4
            L x1 t
            L xt yt
            L x2 t
            L u2 t
            A u1 u1 3cd4 cd4
            L r y1
            L xr yr
            L r y2
            L r v2
            A u1 u1 0 cd4
            L x2 b
            L xb yb
            L x1 b
            L u1 b
            A u1 u1 cd4 cd4
            L l y2
            L xl yl
            L l y1
            Z
            """,
    ]
}
