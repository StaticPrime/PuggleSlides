// DrawingML preset shapes, transcribed from ECMA-376 Part 1's presetShapeDefinitions.xml. See PresetShapeDefinition
// for the statement syntax and the errata fixed.

extension PresetShapeSource {
    static let basic: [String: String] = [
        "arc": """
            av adj1 val 16200000
            av adj2 val 0
            gd stAng pin 0 adj1 21599999
            gd enAng pin 0 adj2 21599999
            gd sw11 +- enAng 0 stAng
            gd sw12 +- sw11 21600000 0
            gd swAng ?: sw11 sw11 sw12
            gd wt1 sin wd2 stAng
            gd ht1 cos hd2 stAng
            gd dx1 cat2 wd2 ht1 wt1
            gd dy1 sat2 hd2 ht1 wt1
            gd wt2 sin wd2 enAng
            gd ht2 cos hd2 enAng
            gd dx2 cat2 wd2 ht2 wt2
            gd dy2 sat2 hd2 ht2 wt2
            gd x1 +- hc dx1 0
            gd y1 +- vc dy1 0
            gd x2 +- hc dx2 0
            gd y2 +- vc dy2 0
            gd sw0 +- 21600000 0 stAng
            gd da1 +- swAng 0 sw0
            gd g1 max x1 x2
            gd ir ?: da1 r g1
            gd sw1 +- cd4 0 stAng
            gd sw2 +- 27000000 0 stAng
            gd sw3 ?: sw1 sw1 sw2
            gd da2 +- swAng 0 sw3
            gd g5 max y1 y2
            gd ib ?: da2 b g5
            gd sw4 +- cd2 0 stAng
            gd sw5 +- 32400000 0 stAng
            gd sw6 ?: sw4 sw4 sw5
            gd da3 +- swAng 0 sw6
            gd g9 min x1 x2
            gd il ?: da3 l g9
            gd sw7 +- 3cd4 0 stAng
            gd sw8 +- 37800000 0 stAng
            gd sw9 ?: sw7 sw7 sw8
            gd da4 +- swAng 0 sw9
            gd g13 min y1 y2
            gd it ?: da4 t g13
            gd cang1 +- stAng 0 cd4
            gd cang2 +- enAng cd4 0
            gd cang3 +/ cang1 cang2 2
            ahPolar gdRefAng=adj1 minAng=0 maxAng=21599999 x=x1 y=y1
            ahPolar gdRefAng=adj2 minAng=0 maxAng=21599999 x=x2 y=y2
            cxn cang1 x1 y1
            cxn cang3 hc vc
            cxn cang2 x2 y2
            rect il it ir ib
            path stroke=false extrusionOk=false
            M x1 y1
            A wd2 hd2 stAng swAng
            L hc vc
            Z
            path fill=none
            M x1 y1
            A wd2 hd2 stAng swAng
            """,
        "bevel": """
            av adj val 12500
            gd a pin 0 adj 50000
            gd x1 */ ss a 100000
            gd x2 +- r 0 x1
            gd y2 +- b 0 x1
            ahXY gdRefX=adj minX=0 maxX=50000 x=x1 y=t
            cxn 0 r vc
            cxn 0 x2 vc
            cxn cd4 hc b
            cxn cd4 hc y2
            cxn cd2 l vc
            cxn cd2 x1 vc
            cxn 3cd4 hc t
            cxn 3cd4 hc x1
            rect x1 x1 x2 y2
            path stroke=false extrusionOk=false
            M x1 x1
            L x2 x1
            L x2 y2
            L x1 y2
            Z
            path fill=lightenLess stroke=false extrusionOk=false
            M l t
            L r t
            L x2 x1
            L x1 x1
            Z
            path fill=darkenLess stroke=false extrusionOk=false
            M l b
            L x1 y2
            L x2 y2
            L r b
            Z
            path fill=lighten stroke=false extrusionOk=false
            M l t
            L x1 x1
            L x1 y2
            L l b
            Z
            path fill=darken stroke=false extrusionOk=false
            M r t
            L r b
            L x2 y2
            L x2 x1
            Z
            path fill=none extrusionOk=false
            M l t
            L r t
            L r b
            L l b
            Z
            M x1 x1
            L x2 x1
            L x2 y2
            L x1 y2
            Z
            M l t
            L x1 x1
            M l b
            L x1 y2
            M r t
            L x2 x1
            M r b
            L x2 y2
            """,
        "blockArc": """
            av adj1 val 10800000
            av adj2 val 0
            av adj3 val 25000
            gd stAng pin 0 adj1 21599999
            gd istAng pin 0 adj2 21599999
            gd a3 pin 0 adj3 50000
            gd sw11 +- istAng 0 stAng
            gd sw12 +- sw11 21600000 0
            gd swAng ?: sw11 sw11 sw12
            gd iswAng +- 0 0 swAng
            gd wt1 sin wd2 stAng
            gd ht1 cos hd2 stAng
            gd wt3 sin wd2 istAng
            gd ht3 cos hd2 istAng
            gd dx1 cat2 wd2 ht1 wt1
            gd dy1 sat2 hd2 ht1 wt1
            gd dx3 cat2 wd2 ht3 wt3
            gd dy3 sat2 hd2 ht3 wt3
            gd x1 +- hc dx1 0
            gd y1 +- vc dy1 0
            gd x3 +- hc dx3 0
            gd y3 +- vc dy3 0
            gd dr */ ss a3 100000
            gd iwd2 +- wd2 0 dr
            gd ihd2 +- hd2 0 dr
            gd wt2 sin iwd2 istAng
            gd ht2 cos ihd2 istAng
            gd wt4 sin iwd2 stAng
            gd ht4 cos ihd2 stAng
            gd dx2 cat2 iwd2 ht2 wt2
            gd dy2 sat2 ihd2 ht2 wt2
            gd dx4 cat2 iwd2 ht4 wt4
            gd dy4 sat2 ihd2 ht4 wt4
            gd x2 +- hc dx2 0
            gd y2 +- vc dy2 0
            gd x4 +- hc dx4 0
            gd y4 +- vc dy4 0
            gd sw0 +- 21600000 0 stAng
            gd da1 +- swAng 0 sw0
            gd g1 max x1 x2
            gd g2 max x3 x4
            gd g3 max g1 g2
            gd ir ?: da1 r g3
            gd sw1 +- cd4 0 stAng
            gd sw2 +- 27000000 0 stAng
            gd sw3 ?: sw1 sw1 sw2
            gd da2 +- swAng 0 sw3
            gd g5 max y1 y2
            gd g6 max y3 y4
            gd g7 max g5 g6
            gd ib ?: da2 b g7
            gd sw4 +- cd2 0 stAng
            gd sw5 +- 32400000 0 stAng
            gd sw6 ?: sw4 sw4 sw5
            gd da3 +- swAng 0 sw6
            gd g9 min x1 x2
            gd g10 min x3 x4
            gd g11 min g9 g10
            gd il ?: da3 l g11
            gd sw7 +- 3cd4 0 stAng
            gd sw8 +- 37800000 0 stAng
            gd sw9 ?: sw7 sw7 sw8
            gd da4 +- swAng 0 sw9
            gd g13 min y1 y2
            gd g14 min y3 y4
            gd g15 min g13 g14
            gd it ?: da4 t g15
            gd x5 +/ x1 x4 2
            gd y5 +/ y1 y4 2
            gd x6 +/ x3 x2 2
            gd y6 +/ y3 y2 2
            gd cang1 +- stAng 0 cd4
            gd cang2 +- istAng cd4 0
            gd cang3 +/ cang1 cang2 2
            ahPolar gdRefAng=adj1 minAng=0 maxAng=21599999 x=x1 y=y1
            ahPolar gdRefR=adj3 minR=0 maxR=50000 gdRefAng=adj2 minAng=0 maxAng=21599999 x=x2 y=y2
            cxn cang1 x5 y5
            cxn cang2 x6 y6
            cxn cang3 hc vc
            rect il it ir ib
            path
            M x1 y1
            A wd2 hd2 stAng swAng
            L x2 y2
            A iwd2 ihd2 istAng iswAng
            Z
            """,
        "bracePair": """
            av adj val 8333
            gd a pin 0 adj 25000
            gd x1 */ ss a 100000
            gd x2 */ ss a 50000
            gd x3 +- r 0 x2
            gd x4 +- r 0 x1
            gd y2 +- vc 0 x1
            gd y3 +- vc x1 0
            gd y4 +- b 0 x1
            gd it */ x1 29289 100000
            gd il +- x1 it 0
            gd ir +- r 0 il
            gd ib +- b 0 it
            ahXY gdRefY=adj minY=0 maxY=25000 x=l y=x1
            cxn 3cd4 hc t
            cxn cd2 l vc
            cxn cd4 hc b
            cxn 0 r vc
            rect il il ir ib
            path stroke=false extrusionOk=false
            M x2 b
            A x1 x1 cd4 cd4
            L x1 y3
            A x1 x1 0 -5400000
            A x1 x1 cd4 -5400000
            L x1 x1
            A x1 x1 cd2 cd4
            L x3 t
            A x1 x1 3cd4 cd4
            L x4 y2
            A x1 x1 cd2 -5400000
            A x1 x1 3cd4 -5400000
            L x4 y4
            A x1 x1 0 cd4
            Z
            path fill=none
            M x2 b
            A x1 x1 cd4 cd4
            L x1 y3
            A x1 x1 0 -5400000
            A x1 x1 cd4 -5400000
            L x1 x1
            A x1 x1 cd2 cd4
            M x3 t
            A x1 x1 3cd4 cd4
            L x4 y2
            A x1 x1 cd2 -5400000
            A x1 x1 3cd4 -5400000
            L x4 y4
            A x1 x1 0 cd4
            """,
        "bracketPair": """
            av adj val 16667
            gd a pin 0 adj 50000
            gd x1 */ ss a 100000
            gd x2 +- r 0 x1
            gd y2 +- b 0 x1
            gd il */ x1 29289 100000
            gd ir +- r 0 il
            gd ib +- b 0 il
            ahXY gdRefY=adj minY=0 maxY=50000 x=l y=x1
            cxn 3cd4 hc t
            cxn cd2 l vc
            cxn cd4 hc b
            cxn 0 r vc
            rect il il ir ib
            path stroke=false extrusionOk=false
            M l x1
            A x1 x1 cd2 cd4
            L x2 t
            A x1 x1 3cd4 cd4
            L r y2
            A x1 x1 0 cd4
            L x1 b
            A x1 x1 cd4 cd4
            Z
            path fill=none
            M x1 b
            A x1 x1 cd4 cd4
            L l x1
            A x1 x1 cd2 cd4
            M x2 t
            A x1 x1 3cd4 cd4
            L r y2
            A x1 x1 0 cd4
            """,
        "can": """
            av adj val 25000
            gd maxAdj */ 50000 h ss
            gd a pin 0 adj maxAdj
            gd y1 */ ss a 200000
            gd y2 +- y1 y1 0
            gd y3 +- b 0 y1
            ahXY gdRefY=adj minY=0 maxY=maxAdj x=hc y=y2
            cxn 3cd4 hc y2
            cxn 3cd4 hc t
            cxn cd2 l vc
            cxn cd4 hc b
            cxn 0 r vc
            rect l y2 r y3
            path stroke=false extrusionOk=false
            M l y1
            A wd2 y1 cd2 -10800000
            L r y3
            A wd2 y1 0 cd2
            Z
            path fill=lighten stroke=false extrusionOk=false
            M l y1
            A wd2 y1 cd2 cd2
            A wd2 y1 0 cd2
            Z
            path fill=none extrusionOk=false
            M r y1
            A wd2 y1 0 cd2
            A wd2 y1 cd2 cd2
            L r y3
            A wd2 y1 0 cd2
            L l y1
            """,
        "chartPlus": """
            path w=10 h=10 fill=none extrusionOk=false
            M 5 0
            L 5 10
            M 0 5
            L 10 5
            path w=10 h=10 stroke=false
            M 0 0
            L 0 10
            L 10 10
            L 10 0
            Z
            """,
        "chartStar": """
            path w=10 h=10 fill=none extrusionOk=false
            M 0 0
            L 10 10
            M 0 10
            L 10 0
            M 5 0
            L 5 10
            path w=10 h=10 stroke=false
            M 0 0
            L 0 10
            L 10 10
            L 10 0
            Z
            """,
        "chartX": """
            path w=10 h=10 fill=none extrusionOk=false
            M 0 0
            L 10 10
            M 0 10
            L 10 0
            path w=10 h=10 stroke=false
            M 0 0
            L 0 10
            L 10 10
            L 10 0
            Z
            """,
        "chord": """
            av adj1 val 2700000
            av adj2 val 16200000
            gd stAng pin 0 adj1 21599999
            gd enAng pin 0 adj2 21599999
            gd sw1 +- enAng 0 stAng
            gd sw2 +- sw1 21600000 0
            gd swAng ?: sw1 sw1 sw2
            gd wt1 sin wd2 stAng
            gd ht1 cos hd2 stAng
            gd dx1 cat2 wd2 ht1 wt1
            gd dy1 sat2 hd2 ht1 wt1
            gd wt2 sin wd2 enAng
            gd ht2 cos hd2 enAng
            gd dx2 cat2 wd2 ht2 wt2
            gd dy2 sat2 hd2 ht2 wt2
            gd x1 +- hc dx1 0
            gd y1 +- vc dy1 0
            gd x2 +- hc dx2 0
            gd y2 +- vc dy2 0
            gd x3 +/ x1 x2 2
            gd y3 +/ y1 y2 2
            gd midAng0 */ swAng 1 2
            gd midAng +- stAng midAng0 cd2
            gd idx cos wd2 2700000
            gd idy sin hd2 2700000
            gd il +- hc 0 idx
            gd ir +- hc idx 0
            gd it +- vc 0 idy
            gd ib +- vc idy 0
            ahPolar gdRefAng=adj1 minAng=0 maxAng=21599999 x=x1 y=y1
            ahPolar gdRefAng=adj2 minAng=0 maxAng=21599999 x=x2 y=y2
            cxn stAng x1 y1
            cxn enAng x2 y2
            cxn midAng x3 y3
            rect il it ir ib
            path
            M x1 y1
            A wd2 hd2 stAng swAng
            Z
            """,
        "cloud": """
            gd il */ w 2977 21600
            gd it */ h 3262 21600
            gd ir */ w 17087 21600
            gd ib */ h 17337 21600
            gd g27 */ w 67 21600
            gd g28 */ h 21577 21600
            gd g29 */ w 21582 21600
            gd g30 */ h 1235 21600
            cxn 0 g29 vc
            cxn cd4 hc g28
            cxn cd2 g27 vc
            cxn 3cd4 hc g30
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
        "corner": """
            av adj1 val 50000
            av adj2 val 50000
            gd maxAdj1 */ 100000 h ss
            gd maxAdj2 */ 100000 w ss
            gd a1 pin 0 adj1 maxAdj1
            gd a2 pin 0 adj2 maxAdj2
            gd x1 */ ss a2 100000
            gd dy1 */ ss a1 100000
            gd y1 +- b 0 dy1
            gd cx1 */ x1 1 2
            gd cy1 +/ y1 b 2
            gd d +- w 0 h
            gd it ?: d y1 t
            gd ir ?: d r x1
            ahXY gdRefY=adj1 minY=0 maxY=maxAdj1 x=l y=y1
            ahXY gdRefX=adj2 minX=0 maxX=maxAdj2 x=x1 y=t
            cxn 0 r cy1
            cxn cd4 hc b
            cxn cd2 l vc
            cxn 3cd4 cx1 t
            rect l it ir b
            path
            M l t
            L x1 t
            L x1 y1
            L r y1
            L r b
            L l b
            Z
            """,
        "cornerTabs": """
            gd md mod w h 0
            gd dx */ 1 md 20
            gd y1 +- 0 b dx
            gd x1 +- 0 r dx
            cxn cd2 l t
            cxn cd2 l dx
            cxn cd2 l y1
            cxn cd2 l b
            cxn 3cd4 dx t
            cxn 3cd4 x1 t
            cxn cd4 dx b
            cxn cd4 x1 b
            cxn 0 r t
            cxn 0 r dx
            cxn 0 r y1
            cxn 0 r b
            rect dx dx x1 y1
            path
            M l t
            L dx t
            L l dx
            Z
            path
            M l y1
            L dx b
            L l b
            Z
            path
            M x1 t
            L r t
            L r dx
            Z
            path
            M r y1
            L r b
            L x1 b
            Z
            """,
        "cube": """
            av adj val 25000
            gd a pin 0 adj 100000
            gd y1 */ ss a 100000
            gd y4 +- b 0 y1
            gd y2 */ y4 1 2
            gd y3 +/ y1 b 2
            gd x4 +- r 0 y1
            gd x2 */ x4 1 2
            gd x3 +/ y1 r 2
            ahXY gdRefY=adj minY=0 maxY=100000 x=l y=y1
            cxn 3cd4 x3 t
            cxn 3cd4 x2 y1
            cxn cd2 l y3
            cxn cd4 x2 b
            cxn 0 x4 y3
            cxn 0 r y2
            rect l y1 x4 b
            path stroke=false extrusionOk=false
            M l y1
            L x4 y1
            L x4 b
            L l b
            Z
            path fill=darkenLess stroke=false extrusionOk=false
            M x4 y1
            L r t
            L r y4
            L x4 b
            Z
            path fill=lightenLess stroke=false extrusionOk=false
            M l y1
            L y1 t
            L r t
            L x4 y1
            Z
            path fill=none extrusionOk=false
            M l y1
            L y1 t
            L r t
            L r y4
            L x4 b
            L l b
            Z
            M l y1
            L x4 y1
            L r t
            M x4 y1
            L x4 b
            """,
        "decagon": """
            av vf val 105146
            gd shd2 */ hd2 vf 100000
            gd dx1 cos wd2 2160000
            gd dx2 cos wd2 4320000
            gd x1 +- hc 0 dx1
            gd x2 +- hc 0 dx2
            gd x3 +- hc dx2 0
            gd x4 +- hc dx1 0
            gd dy1 sin shd2 4320000
            gd dy2 sin shd2 2160000
            gd y1 +- vc 0 dy1
            gd y2 +- vc 0 dy2
            gd y3 +- vc dy2 0
            gd y4 +- vc dy1 0
            cxn 0 x4 y2
            cxn 0 r vc
            cxn 0 x4 y3
            cxn cd4 x3 y4
            cxn cd4 x2 y4
            cxn cd2 x1 y3
            cxn cd2 l vc
            cxn cd2 x1 y2
            cxn 3cd4 x2 y1
            cxn 3cd4 x3 y1
            rect x1 y2 x4 y3
            path
            M l vc
            L x1 y2
            L x2 y1
            L x3 y1
            L x4 y2
            L r vc
            L x4 y3
            L x3 y4
            L x2 y4
            L x1 y3
            Z
            """,
        "diagStripe": """
            av adj val 50000
            gd a pin 0 adj 100000
            gd x2 */ w a 100000
            gd x1 */ x2 1 2
            gd x3 +/ x2 r 2
            gd y2 */ h a 100000
            gd y1 */ y2 1 2
            gd y3 +/ y2 b 2
            ahXY gdRefY=adj minY=0 maxY=100000 x=l y=y2
            cxn 0 hc vc
            cxn cd2 l y3
            cxn cd2 x1 y1
            cxn 3cd4 x3 t
            rect l t x3 y3
            path
            M l y2
            L x2 t
            L r t
            L l b
            Z
            """,
        "diamond": """
            gd ir */ w 3 4
            gd ib */ h 3 4
            cxn 3cd4 hc t
            cxn cd2 l vc
            cxn cd4 hc b
            cxn 0 r vc
            rect wd4 hd4 ir ib
            path
            M l vc
            L hc t
            L r vc
            L hc b
            Z
            """,
        "dodecagon": """
            gd x1 */ w 2894 21600
            gd x2 */ w 7906 21600
            gd x3 */ w 13694 21600
            gd x4 */ w 18706 21600
            gd y1 */ h 2894 21600
            gd y2 */ h 7906 21600
            gd y3 */ h 13694 21600
            gd y4 */ h 18706 21600
            cxn 0 x4 y1
            cxn 0 r y2
            cxn 0 r y3
            cxn 0 x4 y4
            cxn cd4 x3 b
            cxn cd4 x2 b
            cxn cd2 x1 y4
            cxn cd2 l y3
            cxn cd2 l y2
            cxn cd2 x1 y1
            cxn 3cd4 x2 t
            cxn 3cd4 x3 t
            rect x1 y1 x4 y4
            path
            M l y2
            L x1 y1
            L x2 t
            L x3 t
            L x4 y1
            L r y2
            L r y3
            L x4 y4
            L x3 b
            L x2 b
            L x1 y4
            L l y3
            Z
            """,
        "donut": """
            av adj val 25000
            gd a pin 0 adj 50000
            gd dr */ ss a 100000
            gd iwd2 +- wd2 0 dr
            gd ihd2 +- hd2 0 dr
            gd idx cos wd2 2700000
            gd idy sin hd2 2700000
            gd il +- hc 0 idx
            gd ir +- hc idx 0
            gd it +- vc 0 idy
            gd ib +- vc idy 0
            ahPolar gdRefR=adj minR=0 maxR=50000 x=dr y=vc
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
            M dr vc
            A iwd2 ihd2 cd2 -5400000
            A iwd2 ihd2 cd4 -5400000
            A iwd2 ihd2 0 -5400000
            A iwd2 ihd2 3cd4 -5400000
            Z
            """,
        "ellipse": """
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
        "foldedCorner": """
            av adj val 16667
            gd a pin 0 adj 50000
            gd dy2 */ ss a 100000
            gd dy1 */ dy2 1 5
            gd x1 +- r 0 dy2
            gd x2 +- x1 dy1 0
            gd y2 +- b 0 dy2
            gd y1 +- y2 dy1 0
            ahXY gdRefX=adj minX=0 maxX=50000 x=x1 y=b
            cxn 3cd4 hc t
            cxn cd2 l vc
            cxn cd4 hc b
            cxn 0 r vc
            rect l t r y2
            path stroke=false extrusionOk=false
            M l t
            L r t
            L r y2
            L x1 b
            L l b
            Z
            path fill=darkenLess stroke=false extrusionOk=false
            M x1 b
            L x2 y1
            L r y2
            Z
            path fill=none extrusionOk=false
            M x1 b
            L x2 y1
            L r y2
            L x1 b
            L l b
            L l t
            L r t
            L r y2
            """,
        "frame": """
            av adj1 val 12500
            gd a1 pin 0 adj1 50000
            gd x1 */ ss a1 100000
            gd x4 +- r 0 x1
            gd y4 +- b 0 x1
            ahXY gdRefX=adj1 minX=0 maxX=50000 x=x1 y=t
            cxn 3cd4 hc t
            cxn cd2 l vc
            cxn cd4 hc b
            cxn 0 r vc
            rect x1 x1 x4 y4
            path
            M l t
            L r t
            L r b
            L l b
            Z
            M x1 x1
            L x1 y4
            L x4 y4
            L x4 x1
            Z
            """,
        "funnel": """
            gd d */ ss 1 20
            gd rw2 +- wd2 0 d
            gd rh2 +- hd4 0 d
            gd t1 cos wd2 480000
            gd t2 sin hd4 480000
            gd da at2 t1 t2
            gd 2da */ da 2 1
            gd stAng1 +- cd2 0 da
            gd swAng1 +- cd2 2da 0
            gd swAng3 +- cd2 0 2da
            gd rw3 */ wd2 1 4
            gd rh3 */ hd4 1 4
            gd ct1 cos hd4 stAng1
            gd st1 sin wd2 stAng1
            gd m1 mod ct1 st1 0
            gd n1 */ wd2 hd4 m1
            gd dx1 cos n1 stAng1
            gd dy1 sin n1 stAng1
            gd x1 +- hc dx1 0
            gd y1 +- hd4 dy1 0
            gd ct3 cos rh3 da
            gd st3 sin rw3 da
            gd m3 mod ct3 st3 0
            gd n3 */ rw3 rh3 m3
            gd dx3 cos n3 da
            gd dy3 sin n3 da
            gd x3 +- hc dx3 0
            gd vc3 +- b 0 rh3
            gd y2 +- vc3 dy3 0
            gd x2 +- wd2 0 rw2
            gd cd */ cd2 2 1
            rect l t r b
            path
            M x1 y1
            A wd2 hd4 stAng1 swAng1
            L x3 y2
            A rw3 rh3 da swAng3
            Z
            M x2 hd4
            A rw2 rh2 cd2 -21600000
            Z
            """,
        "gear6": """
            av adj1 val 15000
            av adj2 val 3526
            gd a1 pin 0 adj1 20000
            gd a2 pin 0 adj2 5358
            gd th */ ss a1 100000
            gd lFD */ ss a2 100000
            gd th2 */ th 1 2
            gd l2 */ lFD 1 2
            gd l3 +- th2 l2 0
            gd rh +- hd2 0 th
            gd rw +- wd2 0 th
            gd dr +- rw 0 rh
            gd maxr ?: dr rh rw
            gd ha at2 maxr l3
            gd aA1 +- 19800000 0 ha
            gd aD1 +- 19800000 ha 0
            gd ta11 cos rw aA1
            gd ta12 sin rh aA1
            gd bA1 at2 ta11 ta12
            gd cta1 cos rh bA1
            gd sta1 sin rw bA1
            gd ma1 mod cta1 sta1 0
            gd na1 */ rw rh ma1
            gd dxa1 cos na1 bA1
            gd dya1 sin na1 bA1
            gd xA1 +- hc dxa1 0
            gd yA1 +- vc dya1 0
            gd td11 cos rw aD1
            gd td12 sin rh aD1
            gd bD1 at2 td11 td12
            gd ctd1 cos rh bD1
            gd std1 sin rw bD1
            gd md1 mod ctd1 std1 0
            gd nd1 */ rw rh md1
            gd dxd1 cos nd1 bD1
            gd dyd1 sin nd1 bD1
            gd xD1 +- hc dxd1 0
            gd yD1 +- vc dyd1 0
            gd xAD1 +- xA1 0 xD1
            gd yAD1 +- yA1 0 yD1
            gd lAD1 mod xAD1 yAD1 0
            gd a1 at2 yAD1 xAD1
            gd dxF1 sin lFD a1
            gd dyF1 cos lFD a1
            gd xF1 +- xD1 dxF1 0
            gd yF1 +- yD1 dyF1 0
            gd xE1 +- xA1 0 dxF1
            gd yE1 +- yA1 0 dyF1
            gd yC1t sin th a1
            gd xC1t cos th a1
            gd yC1 +- yF1 yC1t 0
            gd xC1 +- xF1 0 xC1t
            gd yB1 +- yE1 yC1t 0
            gd xB1 +- xE1 0 xC1t
            gd aD6 +- 3cd4 ha 0
            gd td61 cos rw aD6
            gd td62 sin rh aD6
            gd bD6 at2 td61 td62
            gd ctd6 cos rh bD6
            gd std6 sin rw bD6
            gd md6 mod ctd6 std6 0
            gd nd6 */ rw rh md6
            gd dxd6 cos nd6 bD6
            gd dyd6 sin nd6 bD6
            gd xD6 +- hc dxd6 0
            gd yD6 +- vc dyd6 0
            gd xA6 +- hc 0 dxd6
            gd xF6 +- xD6 0 lFD
            gd xE6 +- xA6 lFD 0
            gd yC6 +- yD6 0 th
            gd swAng1 +- bA1 0 bD6
            gd aA2 +- 1800000 0 ha
            gd aD2 +- 1800000 ha 0
            gd ta21 cos rw aA2
            gd ta22 sin rh aA2
            gd bA2 at2 ta21 ta22
            gd yA2 +- h 0 yD1
            gd td21 cos rw aD2
            gd td22 sin rh aD2
            gd bD2 at2 td21 td22
            gd yD2 +- h 0 yA1
            gd yC2 +- h 0 yB1
            gd yB2 +- h 0 yC1
            gd xB2 val xC1
            gd swAng2 +- bA2 0 bD1
            gd aD3 +- cd4 ha 0
            gd td31 cos rw aD3
            gd td32 sin rh aD3
            gd bD3 at2 td31 td32
            gd yD3 +- h 0 yD6
            gd yB3 +- h 0 yC6
            gd aD4 +- 9000000 ha 0
            gd td41 cos rw aD4
            gd td42 sin rh aD4
            gd bD4 at2 td41 td42
            gd xD4 +- w 0 xD1
            gd xC4 +- w 0 xC1
            gd xB4 +- w 0 xB1
            gd aD5 +- 12600000 ha 0
            gd td51 cos rw aD5
            gd td52 sin rh aD5
            gd bD5 at2 td51 td52
            gd xD5 +- w 0 xA1
            gd xC5 +- w 0 xB1
            gd xB5 +- w 0 xC1
            gd xCxn1 +/ xB1 xC1 2
            gd yCxn1 +/ yB1 yC1 2
            gd yCxn2 +- b 0 yCxn1
            gd xCxn4 +/ r 0 xCxn1
            ahXY gdRefY=adj1 minY=0 maxY=20000 x=xD6 y=yD6
            ahXY gdRefX=adj2 minX=0 maxX=5358 x=xA6 y=yD6
            cxn 19800000 xCxn1 yCxn1
            cxn 1800000 xCxn1 yCxn2
            cxn cd4 hc yB3
            cxn 9000000 xCxn4 yCxn2
            cxn 12600000 xCxn4 yCxn1
            cxn 3cd4 hc yC6
            rect xD5 yA1 xA1 yD2
            path
            M xA1 yA1
            L xB1 yB1
            L xC1 yC1
            L xD1 yD1
            A rw rh bD1 swAng2
            L xC1 yB2
            L xB1 yC2
            L xA1 yD2
            A rw rh bD2 swAng1
            L xF6 yB3
            L xE6 yB3
            L xA6 yD3
            A rw rh bD3 swAng1
            L xB4 yC2
            L xC4 yB2
            L xD4 yA2
            A rw rh bD4 swAng2
            L xB5 yC1
            L xC5 yB1
            L xD5 yA1
            A rw rh bD5 swAng1
            L xE6 yC6
            L xF6 yC6
            L xD6 yD6
            A rw rh bD6 swAng1
            Z
            """,
        "gear9": """
            av adj1 val 10000
            av adj2 val 1763
            gd a1 pin 0 adj1 20000
            gd a2 pin 0 adj2 2679
            gd th */ ss a1 100000
            gd lFD */ ss a2 100000
            gd th2 */ th 1 2
            gd l2 */ lFD 1 2
            gd l3 +- th2 l2 0
            gd rh +- hd2 0 th
            gd rw +- wd2 0 th
            gd dr +- rw 0 rh
            gd maxr ?: dr rh rw
            gd ha at2 maxr l3
            gd aA1 +- 18600000 0 ha
            gd aD1 +- 18600000 ha 0
            gd ta11 cos rw aA1
            gd ta12 sin rh aA1
            gd bA1 at2 ta11 ta12
            gd cta1 cos rh bA1
            gd sta1 sin rw bA1
            gd ma1 mod cta1 sta1 0
            gd na1 */ rw rh ma1
            gd dxa1 cos na1 bA1
            gd dya1 sin na1 bA1
            gd xA1 +- hc dxa1 0
            gd yA1 +- vc dya1 0
            gd td11 cos rw aD1
            gd td12 sin rh aD1
            gd bD1 at2 td11 td12
            gd ctd1 cos rh bD1
            gd std1 sin rw bD1
            gd md1 mod ctd1 std1 0
            gd nd1 */ rw rh md1
            gd dxd1 cos nd1 bD1
            gd dyd1 sin nd1 bD1
            gd xD1 +- hc dxd1 0
            gd yD1 +- vc dyd1 0
            gd xAD1 +- xA1 0 xD1
            gd yAD1 +- yA1 0 yD1
            gd lAD1 mod xAD1 yAD1 0
            gd a1 at2 yAD1 xAD1
            gd dxF1 sin lFD a1
            gd dyF1 cos lFD a1
            gd xF1 +- xD1 dxF1 0
            gd yF1 +- yD1 dyF1 0
            gd xE1 +- xA1 0 dxF1
            gd yE1 +- yA1 0 dyF1
            gd yC1t sin th a1
            gd xC1t cos th a1
            gd yC1 +- yF1 yC1t 0
            gd xC1 +- xF1 0 xC1t
            gd yB1 +- yE1 yC1t 0
            gd xB1 +- xE1 0 xC1t
            gd aA2 +- 21000000 0 ha
            gd aD2 +- 21000000 ha 0
            gd ta21 cos rw aA2
            gd ta22 sin rh aA2
            gd bA2 at2 ta21 ta22
            gd cta2 cos rh bA2
            gd sta2 sin rw bA2
            gd ma2 mod cta2 sta2 0
            gd na2 */ rw rh ma2
            gd dxa2 cos na2 bA2
            gd dya2 sin na2 bA2
            gd xA2 +- hc dxa2 0
            gd yA2 +- vc dya2 0
            gd td21 cos rw aD2
            gd td22 sin rh aD2
            gd bD2 at2 td21 td22
            gd ctd2 cos rh bD2
            gd std2 sin rw bD2
            gd md2 mod ctd2 std2 0
            gd nd2 */ rw rh md2
            gd dxd2 cos nd2 bD2
            gd dyd2 sin nd2 bD2
            gd xD2 +- hc dxd2 0
            gd yD2 +- vc dyd2 0
            gd xAD2 +- xA2 0 xD2
            gd yAD2 +- yA2 0 yD2
            gd lAD2 mod xAD2 yAD2 0
            gd a2 at2 yAD2 xAD2
            gd dxF2 sin lFD a2
            gd dyF2 cos lFD a2
            gd xF2 +- xD2 dxF2 0
            gd yF2 +- yD2 dyF2 0
            gd xE2 +- xA2 0 dxF2
            gd yE2 +- yA2 0 dyF2
            gd yC2t sin th a2
            gd xC2t cos th a2
            gd yC2 +- yF2 yC2t 0
            gd xC2 +- xF2 0 xC2t
            gd yB2 +- yE2 yC2t 0
            gd xB2 +- xE2 0 xC2t
            gd swAng1 +- bA2 0 bD1
            gd aA3 +- 1800000 0 ha
            gd aD3 +- 1800000 ha 0
            gd ta31 cos rw aA3
            gd ta32 sin rh aA3
            gd bA3 at2 ta31 ta32
            gd cta3 cos rh bA3
            gd sta3 sin rw bA3
            gd ma3 mod cta3 sta3 0
            gd na3 */ rw rh ma3
            gd dxa3 cos na3 bA3
            gd dya3 sin na3 bA3
            gd xA3 +- hc dxa3 0
            gd yA3 +- vc dya3 0
            gd td31 cos rw aD3
            gd td32 sin rh aD3
            gd bD3 at2 td31 td32
            gd ctd3 cos rh bD3
            gd std3 sin rw bD3
            gd md3 mod ctd3 std3 0
            gd nd3 */ rw rh md3
            gd dxd3 cos nd3 bD3
            gd dyd3 sin nd3 bD3
            gd xD3 +- hc dxd3 0
            gd yD3 +- vc dyd3 0
            gd xAD3 +- xA3 0 xD3
            gd yAD3 +- yA3 0 yD3
            gd lAD3 mod xAD3 yAD3 0
            gd a3 at2 yAD3 xAD3
            gd dxF3 sin lFD a3
            gd dyF3 cos lFD a3
            gd xF3 +- xD3 dxF3 0
            gd yF3 +- yD3 dyF3 0
            gd xE3 +- xA3 0 dxF3
            gd yE3 +- yA3 0 dyF3
            gd yC3t sin th a3
            gd xC3t cos th a3
            gd yC3 +- yF3 yC3t 0
            gd xC3 +- xF3 0 xC3t
            gd yB3 +- yE3 yC3t 0
            gd xB3 +- xE3 0 xC3t
            gd swAng2 +- bA3 0 bD2
            gd aA4 +- 4200000 0 ha
            gd aD4 +- 4200000 ha 0
            gd ta41 cos rw aA4
            gd ta42 sin rh aA4
            gd bA4 at2 ta41 ta42
            gd cta4 cos rh bA4
            gd sta4 sin rw bA4
            gd ma4 mod cta4 sta4 0
            gd na4 */ rw rh ma4
            gd dxa4 cos na4 bA4
            gd dya4 sin na4 bA4
            gd xA4 +- hc dxa4 0
            gd yA4 +- vc dya4 0
            gd td41 cos rw aD4
            gd td42 sin rh aD4
            gd bD4 at2 td41 td42
            gd ctd4 cos rh bD4
            gd std4 sin rw bD4
            gd md4 mod ctd4 std4 0
            gd nd4 */ rw rh md4
            gd dxd4 cos nd4 bD4
            gd dyd4 sin nd4 bD4
            gd xD4 +- hc dxd4 0
            gd yD4 +- vc dyd4 0
            gd xAD4 +- xA4 0 xD4
            gd yAD4 +- yA4 0 yD4
            gd lAD4 mod xAD4 yAD4 0
            gd a4 at2 yAD4 xAD4
            gd dxF4 sin lFD a4
            gd dyF4 cos lFD a4
            gd xF4 +- xD4 dxF4 0
            gd yF4 +- yD4 dyF4 0
            gd xE4 +- xA4 0 dxF4
            gd yE4 +- yA4 0 dyF4
            gd yC4t sin th a4
            gd xC4t cos th a4
            gd yC4 +- yF4 yC4t 0
            gd xC4 +- xF4 0 xC4t
            gd yB4 +- yE4 yC4t 0
            gd xB4 +- xE4 0 xC4t
            gd swAng3 +- bA4 0 bD3
            gd aA5 +- 6600000 0 ha
            gd aD5 +- 6600000 ha 0
            gd ta51 cos rw aA5
            gd ta52 sin rh aA5
            gd bA5 at2 ta51 ta52
            gd td51 cos rw aD5
            gd td52 sin rh aD5
            gd bD5 at2 td51 td52
            gd xD5 +- w 0 xA4
            gd xC5 +- w 0 xB4
            gd xB5 +- w 0 xC4
            gd swAng4 +- bA5 0 bD4
            gd aD6 +- 9000000 ha 0
            gd td61 cos rw aD6
            gd td62 sin rh aD6
            gd bD6 at2 td61 td62
            gd xD6 +- w 0 xA3
            gd xC6 +- w 0 xB3
            gd xB6 +- w 0 xC3
            gd aD7 +- 11400000 ha 0
            gd td71 cos rw aD7
            gd td72 sin rh aD7
            gd bD7 at2 td71 td72
            gd xD7 +- w 0 xA2
            gd xC7 +- w 0 xB2
            gd xB7 +- w 0 xC2
            gd aD8 +- 13800000 ha 0
            gd td81 cos rw aD8
            gd td82 sin rh aD8
            gd bD8 at2 td81 td82
            gd xA8 +- w 0 xD1
            gd xD8 +- w 0 xA1
            gd xC8 +- w 0 xB1
            gd xB8 +- w 0 xC1
            gd aA9 +- 3cd4 0 ha
            gd aD9 +- 3cd4 ha 0
            gd td91 cos rw aD9
            gd td92 sin rh aD9
            gd bD9 at2 td91 td92
            gd ctd9 cos rh bD9
            gd std9 sin rw bD9
            gd md9 mod ctd9 std9 0
            gd nd9 */ rw rh md9
            gd dxd9 cos nd9 bD9
            gd dyd9 sin nd9 bD9
            gd xD9 +- hc dxd9 0
            gd yD9 +- vc dyd9 0
            gd ta91 cos rw aA9
            gd ta92 sin rh aA9
            gd bA9 at2 ta91 ta92
            gd xA9 +- hc 0 dxd9
            gd xF9 +- xD9 0 lFD
            gd xE9 +- xA9 lFD 0
            gd yC9 +- yD9 0 th
            gd swAng5 +- bA9 0 bD8
            gd xCxn1 +/ xB1 xC1 2
            gd yCxn1 +/ yB1 yC1 2
            gd xCxn2 +/ xB2 xC2 2
            gd yCxn2 +/ yB2 yC2 2
            gd xCxn3 +/ xB3 xC3 2
            gd yCxn3 +/ yB3 yC3 2
            gd xCxn4 +/ xB4 xC4 2
            gd yCxn4 +/ yB4 yC4 2
            gd xCxn5 +/ r 0 xCxn4
            gd xCxn6 +/ r 0 xCxn3
            gd xCxn7 +/ r 0 xCxn2
            gd xCxn8 +/ r 0 xCxn1
            ahXY gdRefY=adj1 minY=0 maxY=20000 x=xD9 y=yD9
            ahXY gdRefX=adj2 minX=0 maxX=2679 x=xA9 y=yD9
            cxn 18600000 xCxn1 yCxn1
            cxn 21000000 xCxn2 yCxn2
            cxn 1800000 xCxn3 yCxn3
            cxn 4200000 xCxn4 yCxn4
            cxn 6600000 xCxn5 yCxn4
            cxn 9000000 xCxn6 yCxn3
            cxn 11400000 xCxn7 yCxn2
            cxn 13800000 xCxn8 yCxn1
            cxn 3cd4 hc yC9
            rect xA8 yD1 xD1 yD3
            path
            M xA1 yA1
            L xB1 yB1
            L xC1 yC1
            L xD1 yD1
            A rw rh bD1 swAng1
            L xB2 yB2
            L xC2 yC2
            L xD2 yD2
            A rw rh bD2 swAng2
            L xB3 yB3
            L xC3 yC3
            L xD3 yD3
            A rw rh bD3 swAng3
            L xB4 yB4
            L xC4 yC4
            L xD4 yD4
            A rw rh bD4 swAng4
            L xB5 yC4
            L xC5 yB4
            L xD5 yA4
            A rw rh bD5 swAng3
            L xB6 yC3
            L xC6 yB3
            L xD6 yA3
            A rw rh bD6 swAng2
            L xB7 yC2
            L xC7 yB2
            L xD7 yA2
            A rw rh bD7 swAng1
            L xB8 yC1
            L xC8 yB1
            L xD8 yA1
            A rw rh bD8 swAng5
            L xE9 yC9
            L xF9 yC9
            L xD9 yD9
            A rw rh bD9 swAng5
            Z
            """,
        "halfFrame": """
            av adj1 val 33333
            av adj2 val 33333
            gd maxAdj2 */ 100000 w ss
            gd a2 pin 0 adj2 maxAdj2
            gd x1 */ ss a2 100000
            gd g1 */ h x1 w
            gd g2 +- h 0 g1
            gd maxAdj1 */ 100000 g2 ss
            gd a1 pin 0 adj1 maxAdj1
            gd y1 */ ss a1 100000
            gd dx2 */ y1 w h
            gd x2 +- r 0 dx2
            gd dy2 */ x1 h w
            gd y2 +- b 0 dy2
            gd cx1 */ x1 1 2
            gd cy1 +/ y2 b 2
            gd cx2 +/ x2 r 2
            gd cy2 */ y1 1 2
            ahXY gdRefY=adj1 minY=0 maxY=maxAdj1 x=l y=y1
            ahXY gdRefX=adj2 minX=0 maxX=maxAdj2 x=x1 y=t
            cxn 0 cx2 cy2
            cxn cd4 cx1 cy1
            cxn cd2 l vc
            cxn 3cd4 hc t
            rect l t r b
            path
            M l t
            L r t
            L x2 y1
            L x1 y1
            L x1 y2
            L l b
            Z
            """,
        "heart": """
            gd dx1 */ w 49 48
            gd dx2 */ w 10 48
            gd x1 +- hc 0 dx1
            gd x2 +- hc 0 dx2
            gd x3 +- hc dx2 0
            gd x4 +- hc dx1 0
            gd y1 +- t 0 hd3
            gd il */ w 1 6
            gd ir */ w 5 6
            gd ib */ h 2 3
            cxn 3cd4 hc hd4
            cxn cd4 hc b
            rect il hd4 ir ib
            path
            M hc hd4
            C x3 y1 x4 hd4 hc b
            C x1 hd4 x2 y1 hc hd4
            Z
            """,
        "heptagon": """
            av hf val 102572
            av vf val 105210
            gd swd2 */ wd2 hf 100000
            gd shd2 */ hd2 vf 100000
            gd svc */ vc vf 100000
            gd dx1 */ swd2 97493 100000
            gd dx2 */ swd2 78183 100000
            gd dx3 */ swd2 43388 100000
            gd dy1 */ shd2 62349 100000
            gd dy2 */ shd2 22252 100000
            gd dy3 */ shd2 90097 100000
            gd x1 +- hc 0 dx1
            gd x2 +- hc 0 dx2
            gd x3 +- hc 0 dx3
            gd x4 +- hc dx3 0
            gd x5 +- hc dx2 0
            gd x6 +- hc dx1 0
            gd y1 +- svc 0 dy1
            gd y2 +- svc dy2 0
            gd y3 +- svc dy3 0
            gd ib +- b 0 y1
            cxn 0 x5 y1
            cxn 0 x6 y2
            cxn cd4 x4 y3
            cxn cd4 x3 y3
            cxn cd2 x1 y2
            cxn cd2 x2 y1
            cxn 3cd4 hc t
            rect x2 y1 x5 ib
            path
            M x1 y2
            L x2 y1
            L hc t
            L x5 y1
            L x6 y2
            L x4 y3
            L x3 y3
            Z
            """,
        "hexagon": """
            av adj val 25000
            av vf val 115470
            gd maxAdj */ 50000 w ss
            gd a pin 0 adj maxAdj
            gd shd2 */ hd2 vf 100000
            gd x1 */ ss a 100000
            gd x2 +- r 0 x1
            gd dy1 sin shd2 3600000
            gd y1 +- vc 0 dy1
            gd y2 +- vc dy1 0
            gd q1 */ maxAdj -1 2
            gd q2 +- a q1 0
            gd q3 ?: q2 4 2
            gd q4 ?: q2 3 2
            gd q5 ?: q2 q1 0
            gd q6 +/ a q5 q1
            gd q7 */ q6 q4 -1
            gd q8 +- q3 q7 0
            gd il */ w q8 24
            gd it */ h q8 24
            gd ir +- r 0 il
            gd ib +- b 0 it
            ahXY gdRefX=adj minX=0 maxX=maxAdj x=x1 y=t
            cxn 0 r vc
            cxn cd4 x2 y2
            cxn cd4 x1 y2
            cxn cd2 l vc
            cxn 3cd4 x1 y1
            cxn 3cd4 x2 y1
            rect il it ir ib
            path
            M l vc
            L x1 y1
            L x2 y1
            L r vc
            L x2 y2
            L x1 y2
            Z
            """,
        "leftBrace": """
            av adj1 val 8333
            av adj2 val 50000
            gd a2 pin 0 adj2 100000
            gd q1 +- 100000 0 a2
            gd q2 min q1 a2
            gd q3 */ q2 1 2
            gd maxAdj1 */ q3 h ss
            gd a1 pin 0 adj1 maxAdj1
            gd y1 */ ss a1 100000
            gd y3 */ h a2 100000
            gd y4 +- y3 y1 0
            gd dx1 cos wd2 2700000
            gd dy1 sin y1 2700000
            gd il +- r 0 dx1
            gd it +- y1 0 dy1
            gd ib +- b dy1 y1
            ahXY gdRefY=adj1 minY=0 maxY=maxAdj1 x=hc y=y1
            ahXY gdRefY=adj2 minY=0 maxY=100000 x=l y=y3
            cxn cd4 r t
            cxn cd2 l y3
            cxn 3cd4 r b
            rect il it r ib
            path stroke=false extrusionOk=false
            M r b
            A wd2 y1 cd4 cd4
            L hc y4
            A wd2 y1 0 -5400000
            A wd2 y1 cd4 -5400000
            L hc y1
            A wd2 y1 cd2 cd4
            Z
            path fill=none
            M r b
            A wd2 y1 cd4 cd4
            L hc y4
            A wd2 y1 0 -5400000
            A wd2 y1 cd4 -5400000
            L hc y1
            A wd2 y1 cd2 cd4
            """,
        "leftBracket": """
            av adj val 8333
            gd maxAdj */ 50000 h ss
            gd a pin 0 adj maxAdj
            gd y1 */ ss a 100000
            gd y2 +- b 0 y1
            gd dx1 cos w 2700000
            gd dy1 sin y1 2700000
            gd il +- r 0 dx1
            gd it +- y1 0 dy1
            gd ib +- b dy1 y1
            ahXY gdRefY=adj minY=0 maxY=maxAdj x=l y=y1
            cxn cd4 r t
            cxn cd2 l vc
            cxn 3cd4 r b
            rect il it r ib
            path stroke=false extrusionOk=false
            M r b
            A w y1 cd4 cd4
            L l y1
            A w y1 cd2 cd4
            Z
            path fill=none
            M r b
            A w y1 cd4 cd4
            L l y1
            A w y1 cd2 cd4
            """,
        "lightningBolt": """
            gd x1 */ w 5022 21600
            gd x3 */ w 8472 21600
            gd x4 */ w 8757 21600
            gd x5 */ w 10012 21600
            gd x8 */ w 12860 21600
            gd x9 */ w 13917 21600
            gd x11 */ w 16577 21600
            gd y1 */ h 3890 21600
            gd y2 */ h 6080 21600
            gd y4 */ h 7437 21600
            gd y6 */ h 9705 21600
            gd y7 */ h 12007 21600
            gd y10 */ h 14277 21600
            gd y11 */ h 14915 21600
            cxn 3cd4 x3 t
            cxn 3cd4 l y1
            cxn cd2 x1 y6
            cxn cd2 x5 y11
            cxn cd4 r b
            cxn 0 x11 y7
            cxn 0 x8 y2
            rect x4 y4 x9 y10
            path w=21600 h=21600
            M 8472 0
            L 12860 6080
            L 11050 6797
            L 16577 12007
            L 14767 12877
            L 21600 21600
            L 10012 14915
            L 12222 13987
            L 5022 9705
            L 7602 8382
            L 0 3890
            Z
            """,
        "mathDivide": """
            av adj1 val 23520
            av adj2 val 5880
            av adj3 val 11760
            gd a1 pin 1000 adj1 36745
            gd ma1 +- 0 0 a1
            gd ma3h +/ 73490 ma1 4
            gd ma3w */ 36745 w h
            gd maxAdj3 min ma3h ma3w
            gd a3 pin 1000 adj3 maxAdj3
            gd m4a3 */ -4 a3 1
            gd maxAdj2 +- 73490 m4a3 a1
            gd a2 pin 0 adj2 maxAdj2
            gd dy1 */ h a1 200000
            gd yg */ h a2 100000
            gd rad */ h a3 100000
            gd dx1 */ w 73490 200000
            gd y3 +- vc 0 dy1
            gd y4 +- vc dy1 0
            gd a +- yg rad 0
            gd y2 +- y3 0 a
            gd y1 +- y2 0 rad
            gd y5 +- b 0 y1
            gd x1 +- hc 0 dx1
            gd x3 +- hc dx1 0
            gd x2 +- hc 0 rad
            ahXY gdRefY=adj1 minY=1000 maxY=36745 x=l y=y3
            ahXY gdRefY=adj2 minY=0 maxY=maxAdj2 x=r y=y2
            ahXY gdRefX=adj3 minX=1000 maxX=maxAdj3 x=x2 y=t
            cxn 0 x3 vc
            cxn cd4 hc y5
            cxn cd2 x1 vc
            cxn 3cd4 hc y1
            rect x1 y3 x3 y4
            path
            M hc y1
            A rad rad 3cd4 21600000
            Z
            M hc y5
            A rad rad cd4 21600000
            Z
            M x1 y3
            L x3 y3
            L x3 y4
            L x1 y4
            Z
            """,
        "mathEqual": """
            av adj1 val 23520
            av adj2 val 11760
            gd a1 pin 0 adj1 36745
            gd 2a1 */ a1 2 1
            gd mAdj2 +- 100000 0 2a1
            gd a2 pin 0 adj2 mAdj2
            gd dy1 */ h a1 100000
            gd dy2 */ h a2 200000
            gd dx1 */ w 73490 200000
            gd y2 +- vc 0 dy2
            gd y3 +- vc dy2 0
            gd y1 +- y2 0 dy1
            gd y4 +- y3 dy1 0
            gd x1 +- hc 0 dx1
            gd x2 +- hc dx1 0
            gd yC1 +/ y1 y2 2
            gd yC2 +/ y3 y4 2
            ahXY gdRefY=adj1 minY=0 maxY=36745 x=l y=y1
            ahXY gdRefY=adj2 minY=0 maxY=mAdj2 x=r y=y2
            cxn 0 x2 yC1
            cxn 0 x2 yC2
            cxn cd4 hc y4
            cxn cd2 x1 yC1
            cxn cd2 x1 yC2
            cxn 3cd4 hc y1
            rect x1 y1 x2 y4
            path
            M x1 y1
            L x2 y1
            L x2 y2
            L x1 y2
            Z
            M x1 y3
            L x2 y3
            L x2 y4
            L x1 y4
            Z
            """,
        "mathMinus": """
            av adj1 val 23520
            gd a1 pin 0 adj1 100000
            gd dy1 */ h a1 200000
            gd dx1 */ w 73490 200000
            gd y1 +- vc 0 dy1
            gd y2 +- vc dy1 0
            gd x1 +- hc 0 dx1
            gd x2 +- hc dx1 0
            ahXY gdRefY=adj1 minY=0 maxY=100000 x=l y=y1
            cxn 0 x2 vc
            cxn cd4 hc y2
            cxn cd2 x1 vc
            cxn 3cd4 hc y1
            rect x1 y1 x2 y2
            path
            M x1 y1
            L x2 y1
            L x2 y2
            L x1 y2
            Z
            """,
        "mathMultiply": """
            av adj1 val 23520
            gd a1 pin 0 adj1 51965
            gd th */ ss a1 100000
            gd a at2 w h
            gd sa sin 1 a
            gd ca cos 1 a
            gd ta tan 1 a
            gd dl mod w h 0
            gd rw */ dl 51965 100000
            gd lM +- dl 0 rw
            gd xM */ ca lM 2
            gd yM */ sa lM 2
            gd dxAM */ sa th 2
            gd dyAM */ ca th 2
            gd xA +- xM 0 dxAM
            gd yA +- yM dyAM 0
            gd xB +- xM dxAM 0
            gd yB +- yM 0 dyAM
            gd xBC +- hc 0 xB
            gd yBC */ xBC ta 1
            gd yC +- yBC yB 0
            gd xD +- r 0 xB
            gd xE +- r 0 xA
            gd yFE +- vc 0 yA
            gd xFE */ yFE 1 ta
            gd xF +- xE 0 xFE
            gd xL +- xA xFE 0
            gd yG +- b 0 yA
            gd yH +- b 0 yB
            gd yI +- b 0 yC
            gd xC2 +- r 0 xM
            gd yC3 +- b 0 yM
            ahXY gdRefY=adj1 minY=0 maxY=51965 x=l y=th
            cxn cd2 xM yM
            cxn 3cd4 xC2 yM
            cxn 0 xC2 yC3
            cxn cd4 xM yC3
            rect xA yB xE yH
            path
            M xA yA
            L xB yB
            L hc yC
            L xD yB
            L xE yA
            L xF vc
            L xE yG
            L xD yH
            L hc yI
            L xB yH
            L xA yG
            L xL vc
            Z
            """,
        "mathNotEqual": """
            av adj1 val 23520
            av adj2 val 6600000
            av adj3 val 11760
            gd a1 pin 0 adj1 50000
            gd crAng pin 4200000 adj2 6600000
            gd 2a1 */ a1 2 1
            gd maxAdj3 +- 100000 0 2a1
            gd a3 pin 0 adj3 maxAdj3
            gd dy1 */ h a1 100000
            gd dy2 */ h a3 200000
            gd dx1 */ w 73490 200000
            gd x1 +- hc 0 dx1
            gd x8 +- hc dx1 0
            gd y2 +- vc 0 dy2
            gd y3 +- vc dy2 0
            gd y1 +- y2 0 dy1
            gd y4 +- y3 dy1 0
            gd cadj2 +- crAng 0 cd4
            gd xadj2 tan hd2 cadj2
            gd len mod xadj2 hd2 0
            gd bhw */ len dy1 hd2
            gd bhw2 */ bhw 1 2
            gd x7 +- hc xadj2 bhw2
            gd dx67 */ xadj2 y1 hd2
            gd x6 +- x7 0 dx67
            gd dx57 */ xadj2 y2 hd2
            gd x5 +- x7 0 dx57
            gd dx47 */ xadj2 y3 hd2
            gd x4 +- x7 0 dx47
            gd dx37 */ xadj2 y4 hd2
            gd x3 +- x7 0 dx37
            gd dx27 */ xadj2 2 1
            gd x2 +- x7 0 dx27
            gd rx7 +- x7 bhw 0
            gd rx6 +- x6 bhw 0
            gd rx5 +- x5 bhw 0
            gd rx4 +- x4 bhw 0
            gd rx3 +- x3 bhw 0
            gd rx2 +- x2 bhw 0
            gd dx7 */ dy1 hd2 len
            gd rxt +- x7 dx7 0
            gd lxt +- rx7 0 dx7
            gd rx ?: cadj2 rxt rx7
            gd lx ?: cadj2 x7 lxt
            gd dy3 */ dy1 xadj2 len
            gd dy4 +- 0 0 dy3
            gd ry ?: cadj2 dy3 t
            gd ly ?: cadj2 t dy4
            gd dlx +- w 0 rx
            gd drx +- w 0 lx
            gd dly +- h 0 ry
            gd dry +- h 0 ly
            gd xC1 +/ rx lx 2
            gd xC2 +/ drx dlx 2
            gd yC1 +/ ry ly 2
            gd yC2 +/ y1 y2 2
            gd yC3 +/ y3 y4 2
            gd yC4 +/ dry dly 2
            ahXY gdRefY=adj1 minY=0 maxY=50000 x=l y=y1
            ahPolar gdRefAng=adj2 minAng=4200000 maxAng=6600000 x=lx y=t
            ahXY gdRefY=adj3 minY=0 maxY=maxAdj3 x=r y=y2
            cxn 0 x8 yC2
            cxn 0 x8 yC3
            cxn cd4 xC2 yC4
            cxn cd2 x1 yC2
            cxn cd2 x1 yC3
            cxn 3cd4 xC1 yC1
            rect x1 y1 x8 y4
            path
            M x1 y1
            L x6 y1
            L lx ly
            L rx ry
            L rx6 y1
            L x8 y1
            L x8 y2
            L rx5 y2
            L rx4 y3
            L x8 y3
            L x8 y4
            L rx3 y4
            L drx dry
            L dlx dly
            L x3 y4
            L x1 y4
            L x1 y3
            L x4 y3
            L x5 y2
            L x1 y2
            Z
            """,
        "mathPlus": """
            av adj1 val 23520
            gd a1 pin 0 adj1 73490
            gd dx1 */ w 73490 200000
            gd dy1 */ h 73490 200000
            gd dx2 */ ss a1 200000
            gd x1 +- hc 0 dx1
            gd x2 +- hc 0 dx2
            gd x3 +- hc dx2 0
            gd x4 +- hc dx1 0
            gd y1 +- vc 0 dy1
            gd y2 +- vc 0 dx2
            gd y3 +- vc dx2 0
            gd y4 +- vc dy1 0
            ahXY gdRefY=adj1 minY=0 maxY=73490 x=l y=y2
            cxn 0 x4 vc
            cxn cd4 hc y4
            cxn cd2 x1 vc
            cxn 3cd4 hc y1
            rect x1 y2 x4 y3
            path
            M x1 y2
            L x2 y2
            L x2 y1
            L x3 y1
            L x3 y2
            L x4 y2
            L x4 y3
            L x3 y3
            L x3 y4
            L x2 y4
            L x2 y3
            L x1 y3
            Z
            """,
        "moon": """
            av adj val 50000
            gd a pin 0 adj 87500
            gd g0 */ ss a 100000
            gd g0w */ g0 w ss
            gd g1 +- ss 0 g0
            gd g2 */ g0 g0 g1
            gd g3 */ ss ss g1
            gd g4 */ g3 2 1
            gd g5 +- g4 0 g2
            gd g6 +- g5 0 g0
            gd g6w */ g6 w ss
            gd g7 */ g5 1 2
            gd g8 +- g7 0 g0
            gd dy1 */ g8 hd2 ss
            gd g10h +- vc 0 dy1
            gd g11h +- vc dy1 0
            gd g12 */ g0 9598 32768
            gd g12w */ g12 w ss
            gd g13 +- ss 0 g12
            gd q1 */ ss ss 1
            gd q2 */ g13 g13 1
            gd q3 +- q1 0 q2
            gd q4 sqrt q3
            gd dy4 */ q4 hd2 ss
            gd g15h +- vc 0 dy4
            gd g16h +- vc dy4 0
            gd g17w +- g6w 0 g0w
            gd g18w */ g17w 1 2
            gd dx2p +- g0w g18w w
            gd dx2 */ dx2p -1 1
            gd dy2 */ hd2 -1 1
            gd stAng1 at2 dx2 dy2
            gd enAngp1 at2 dx2 hd2
            gd enAng1 +- enAngp1 0 21600000
            gd swAng1 +- enAng1 0 stAng1
            ahXY gdRefX=adj minX=0 maxX=87500 x=g0w y=vc
            cxn 3cd4 r t
            cxn cd2 l vc
            cxn cd4 r b
            cxn 0 g0w vc
            rect g12w g15h g0w g16h
            path
            M r b
            A w hd2 cd4 cd2
            A g18w dy1 stAng1 swAng1
            Z
            """,
        "noSmoking": """
            av adj val 18750
            gd a pin 0 adj 50000
            gd dr */ ss a 100000
            gd iwd2 +- wd2 0 dr
            gd ihd2 +- hd2 0 dr
            gd ang at2 w h
            gd ct cos ihd2 ang
            gd st sin iwd2 ang
            gd m mod ct st 0
            gd n */ iwd2 ihd2 m
            gd drd2 */ dr 1 2
            gd dang at2 n drd2
            gd dang2 */ dang 2 1
            gd swAng +- -10800000 dang2 0
            gd t3 at2 w h
            gd stAng1 +- t3 0 dang
            gd stAng2 +- stAng1 0 cd2
            gd ct1 cos ihd2 stAng1
            gd st1 sin iwd2 stAng1
            gd m1 mod ct1 st1 0
            gd n1 */ iwd2 ihd2 m1
            gd dx1 cos n1 stAng1
            gd dy1 sin n1 stAng1
            gd x1 +- hc dx1 0
            gd y1 +- vc dy1 0
            gd x2 +- hc 0 dx1
            gd y2 +- vc 0 dy1
            gd idx cos wd2 2700000
            gd idy sin hd2 2700000
            gd il +- hc 0 idx
            gd ir +- hc idx 0
            gd it +- vc 0 idy
            gd ib +- vc idy 0
            ahPolar gdRefR=adj minR=0 maxR=50000 x=dr y=vc
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
            M x1 y1
            A iwd2 ihd2 stAng1 swAng
            Z
            M x2 y2
            A iwd2 ihd2 stAng2 swAng
            Z
            """,
        "nonIsoscelesTrapezoid": """
            av adj1 val 25000
            av adj2 val 25000
            gd maxAdj */ 50000 w ss
            gd a1 pin 0 adj1 maxAdj
            gd a2 pin 0 adj2 maxAdj
            gd x1 */ ss a1 200000
            gd x2 */ ss a1 100000
            gd dx3 */ ss a2 100000
            gd x3 +- r 0 dx3
            gd x4 +/ r x3 2
            gd il */ wd3 a1 maxAdj
            gd adjm max a1 a2
            gd it */ hd3 adjm maxAdj
            gd irt */ wd3 a2 maxAdj
            gd ir +- r 0 irt
            ahXY gdRefX=adj1 minX=0 maxX=maxAdj x=x2 y=t
            ahXY gdRefX=adj2 minX=0 maxX=maxAdj x=x3 y=t
            cxn 0 x4 vc
            cxn cd4 hc b
            cxn cd2 x1 vc
            cxn 3cd4 hc t
            rect il it ir b
            path
            M l b
            L x2 t
            L x3 t
            L r b
            Z
            """,
        "octagon": """
            av adj val 29289
            gd a pin 0 adj 50000
            gd x1 */ ss a 100000
            gd x2 +- r 0 x1
            gd y2 +- b 0 x1
            gd il */ x1 1 2
            gd ir +- r 0 il
            gd ib +- b 0 il
            ahXY gdRefX=adj minX=0 maxX=50000 x=x1 y=t
            cxn 0 r x1
            cxn 0 r y2
            cxn cd4 x2 b
            cxn cd4 x1 b
            cxn cd2 l y2
            cxn cd2 l x1
            cxn 3cd4 x1 t
            cxn 3cd4 x2 t
            rect il il ir ib
            path
            M l x1
            L x1 t
            L x2 t
            L r x1
            L r y2
            L x2 b
            L x1 b
            L l y2
            Z
            """,
        "parallelogram": """
            av adj val 25000
            gd maxAdj */ 100000 w ss
            gd a pin 0 adj maxAdj
            gd x1 */ ss a 200000
            gd x2 */ ss a 100000
            gd x6 +- r 0 x1
            gd x5 +- r 0 x2
            gd x3 */ x5 1 2
            gd x4 +- r 0 x3
            gd il */ wd2 a maxAdj
            gd q1 */ 5 a maxAdj
            gd q2 +/ 1 q1 12
            gd il */ q2 w 1
            gd it */ q2 h 1
            gd ir +- r 0 il
            gd ib +- b 0 it
            gd q3 */ h hc x2
            gd y1 pin 0 q3 h
            gd y2 +- b 0 y1
            ahXY gdRefX=adj minX=0 maxX=maxAdj x=x2 y=t
            cxn 3cd4 hc y2
            cxn 3cd4 x4 t
            cxn 0 x6 vc
            cxn cd4 x3 b
            cxn cd4 hc y1
            cxn cd2 x1 vc
            rect il it ir ib
            path
            M l b
            L x2 t
            L r t
            L x5 b
            Z
            """,
        "pentagon": """
            av hf val 105146
            av vf val 110557
            gd swd2 */ wd2 hf 100000
            gd shd2 */ hd2 vf 100000
            gd svc */ vc vf 100000
            gd dx1 cos swd2 1080000
            gd dx2 cos swd2 18360000
            gd dy1 sin shd2 1080000
            gd dy2 sin shd2 18360000
            gd x1 +- hc 0 dx1
            gd x2 +- hc 0 dx2
            gd x3 +- hc dx2 0
            gd x4 +- hc dx1 0
            gd y1 +- svc 0 dy1
            gd y2 +- svc 0 dy2
            gd it */ y1 dx2 dx1
            cxn 3cd4 hc t
            cxn cd2 x1 y1
            cxn cd4 x2 y2
            cxn cd4 hc b
            cxn cd4 x3 y2
            cxn 0 x4 y1
            rect x2 it x3 y2
            path
            M x1 y1
            L hc t
            L x4 y1
            L x3 y2
            L x2 y2
            Z
            """,
        "pie": """
            av adj1 val 0
            av adj2 val 16200000
            gd stAng pin 0 adj1 21599999
            gd enAng pin 0 adj2 21599999
            gd sw1 +- enAng 0 stAng
            gd sw2 +- sw1 21600000 0
            gd swAng ?: sw1 sw1 sw2
            gd wt1 sin wd2 stAng
            gd ht1 cos hd2 stAng
            gd dx1 cat2 wd2 ht1 wt1
            gd dy1 sat2 hd2 ht1 wt1
            gd x1 +- hc dx1 0
            gd y1 +- vc dy1 0
            gd wt2 sin wd2 enAng
            gd ht2 cos hd2 enAng
            gd dx2 cat2 wd2 ht2 wt2
            gd dy2 sat2 hd2 ht2 wt2
            gd x2 +- hc dx2 0
            gd y2 +- vc dy2 0
            gd idx cos wd2 2700000
            gd idy sin hd2 2700000
            gd il +- hc 0 idx
            gd ir +- hc idx 0
            gd it +- vc 0 idy
            gd ib +- vc idy 0
            ahPolar gdRefAng=adj1 minAng=0 maxAng=21599999 x=x1 y=y1
            ahPolar gdRefAng=adj2 minAng=0 maxAng=21599999 x=x2 y=y2
            cxn 0 r vc
            cxn cd4 hc b
            cxn cd2 l vc
            cxn 3cd4 hc t
            rect il it ir ib
            path
            M x1 y1
            A wd2 hd2 stAng swAng
            L hc vc
            Z
            """,
        "pieWedge": """
            gd g1 cos w 13500000
            gd g2 sin h 13500000
            gd x1 +- r g1 0
            gd y1 +- b g2 0
            cxn 0 r vc
            cxn cd4 hc b
            rect x1 y1 r b
            path
            M l b
            A w h cd2 cd4
            L r b
            Z
            """,
        "plaque": """
            av adj val 16667
            gd a pin 0 adj 50000
            gd x1 */ ss a 100000
            gd x2 +- r 0 x1
            gd y2 +- b 0 x1
            gd il */ x1 70711 100000
            gd ir +- r 0 il
            gd ib +- b 0 il
            ahXY gdRefX=adj minX=0 maxX=50000 x=x1 y=t
            cxn 3cd4 hc t
            cxn cd2 l vc
            cxn cd4 hc b
            cxn 0 r vc
            rect il il ir ib
            path
            M l x1
            A x1 x1 cd4 -5400000
            L x2 t
            A x1 x1 cd2 -5400000
            L r y2
            A x1 x1 3cd4 -5400000
            L x1 b
            A x1 x1 0 -5400000
            Z
            """,
        "plaqueTabs": """
            gd md mod w h 0
            gd dx */ 1 md 20
            gd y1 +- 0 b dx
            gd x1 +- 0 r dx
            cxn cd2 l t
            cxn cd2 l dx
            cxn cd2 l y1
            cxn cd2 l b
            cxn 3cd4 dx t
            cxn 3cd4 x1 t
            cxn cd4 dx b
            cxn cd4 x1 b
            cxn 0 r t
            cxn 0 r dx
            cxn 0 r y1
            cxn 0 r b
            rect dx dx x1 y1
            path
            M l t
            L dx t
            A dx dx 0 cd4
            Z
            path
            M l y1
            A dx dx 3cd4 cd4
            L l b
            Z
            path
            M r t
            L r dx
            A dx dx cd4 cd4
            Z
            path
            M x1 b
            A dx dx cd2 cd4
            L r b
            Z
            """,
        "plus": """
            av adj val 25000
            gd a pin 0 adj 50000
            gd x1 */ ss a 100000
            gd x2 +- r 0 x1
            gd y2 +- b 0 x1
            gd d +- w 0 h
            gd il ?: d l x1
            gd ir ?: d r x2
            gd it ?: d x1 t
            gd ib ?: d y2 b
            ahXY gdRefX=adj minX=0 maxX=50000 x=x1 y=t
            cxn 3cd4 hc t
            cxn cd2 l vc
            cxn cd4 hc b
            cxn 0 r vc
            rect il it ir ib
            path
            M l x1
            L x1 x1
            L x1 t
            L x2 t
            L x2 x1
            L r x1
            L r y2
            L x2 y2
            L x2 b
            L x1 b
            L x1 y2
            L l y2
            Z
            """,
        "rect": """
            cxn 3cd4 hc t
            cxn cd2 l vc
            cxn cd4 hc b
            cxn 0 r vc
            rect l t r b
            path
            M l t
            L r t
            L r b
            L l b
            Z
            """,
        "rightBrace": """
            av adj1 val 8333
            av adj2 val 50000
            gd a2 pin 0 adj2 100000
            gd q1 +- 100000 0 a2
            gd q2 min q1 a2
            gd q3 */ q2 1 2
            gd maxAdj1 */ q3 h ss
            gd a1 pin 0 adj1 maxAdj1
            gd y1 */ ss a1 100000
            gd y3 */ h a2 100000
            gd y2 +- y3 0 y1
            gd y4 +- b 0 y1
            gd dx1 cos wd2 2700000
            gd dy1 sin y1 2700000
            gd ir +- l dx1 0
            gd it +- y1 0 dy1
            gd ib +- b dy1 y1
            ahXY gdRefY=adj1 minY=0 maxY=maxAdj1 x=hc y=y1
            ahXY gdRefY=adj2 minY=0 maxY=100000 x=r y=y3
            cxn cd4 l t
            cxn cd2 r y3
            cxn 3cd4 l b
            rect l it ir ib
            path stroke=false extrusionOk=false
            M l t
            A wd2 y1 3cd4 cd4
            L hc y2
            A wd2 y1 cd2 -5400000
            A wd2 y1 3cd4 -5400000
            L hc y4
            A wd2 y1 0 cd4
            Z
            path fill=none
            M l t
            A wd2 y1 3cd4 cd4
            L hc y2
            A wd2 y1 cd2 -5400000
            A wd2 y1 3cd4 -5400000
            L hc y4
            A wd2 y1 0 cd4
            """,
        "rightBracket": """
            av adj val 8333
            gd maxAdj */ 50000 h ss
            gd a pin 0 adj maxAdj
            gd y1 */ ss a 100000
            gd y2 +- b 0 y1
            gd dx1 cos w 2700000
            gd dy1 sin y1 2700000
            gd ir +- l dx1 0
            gd it +- y1 0 dy1
            gd ib +- b dy1 y1
            ahXY gdRefY=adj minY=0 maxY=maxAdj x=r y=y1
            cxn cd4 l t
            cxn 3cd4 l b
            cxn cd2 r vc
            rect l it ir ib
            path stroke=false extrusionOk=false
            M l t
            A w y1 3cd4 cd4
            L r y2
            A w y1 0 cd4
            Z
            path fill=none
            M l t
            A w y1 3cd4 cd4
            L r y2
            A w y1 0 cd4
            """,
        "round1Rect": """
            av adj val 16667
            gd a pin 0 adj 50000
            gd dx1 */ ss a 100000
            gd x1 +- r 0 dx1
            gd idx */ dx1 29289 100000
            gd ir +- r 0 idx
            ahXY gdRefX=adj minX=0 maxX=50000 x=x1 y=t
            cxn 3cd4 hc t
            cxn cd2 l vc
            cxn cd4 hc b
            cxn 0 r vc
            rect l t ir b
            path
            M l t
            L x1 t
            A dx1 dx1 3cd4 cd4
            L r b
            L l b
            Z
            """,
        "round2DiagRect": """
            av adj1 val 16667
            av adj2 val 0
            gd a1 pin 0 adj1 50000
            gd a2 pin 0 adj2 50000
            gd x1 */ ss a1 100000
            gd y1 +- b 0 x1
            gd a */ ss a2 100000
            gd x2 +- r 0 a
            gd y2 +- b 0 a
            gd dx1 */ x1 29289 100000
            gd dx2 */ a 29289 100000
            gd d +- dx1 0 dx2
            gd dx ?: d dx1 dx2
            gd ir +- r 0 dx
            gd ib +- b 0 dx
            ahXY gdRefX=adj1 minX=0 maxX=50000 x=x1 y=t
            ahXY gdRefX=adj2 minX=0 maxX=50000 x=x2 y=t
            cxn 0 r vc
            cxn cd4 hc b
            cxn cd2 l vc
            cxn 3cd4 hc t
            rect dx dx ir ib
            path
            M x1 t
            L x2 t
            A a a 3cd4 cd4
            L r y1
            A x1 x1 0 cd4
            L a b
            A a a cd4 cd4
            L l x1
            A x1 x1 cd2 cd4
            Z
            """,
        "round2SameRect": """
            av adj1 val 16667
            av adj2 val 0
            gd a1 pin 0 adj1 50000
            gd a2 pin 0 adj2 50000
            gd tx1 */ ss a1 100000
            gd tx2 +- r 0 tx1
            gd bx1 */ ss a2 100000
            gd bx2 +- r 0 bx1
            gd by1 +- b 0 bx1
            gd d +- tx1 0 bx1
            gd tdx */ tx1 29289 100000
            gd bdx */ bx1 29289 100000
            gd il ?: d tdx bdx
            gd ir +- r 0 il
            gd ib +- b 0 bdx
            ahXY gdRefX=adj1 minX=0 maxX=50000 x=tx2 y=t
            ahXY gdRefX=adj2 minX=0 maxX=50000 x=bx1 y=b
            cxn 0 r vc
            cxn cd4 hc b
            cxn cd2 l vc
            cxn 3cd4 hc t
            rect il tdx ir ib
            path
            M tx1 t
            L tx2 t
            A tx1 tx1 3cd4 cd4
            L r by1
            A bx1 bx1 0 cd4
            L bx1 b
            A bx1 bx1 cd4 cd4
            L l tx1
            A tx1 tx1 cd2 cd4
            Z
            """,
        "roundRect": """
            av adj val 16667
            gd a pin 0 adj 50000
            gd x1 */ ss a 100000
            gd x2 +- r 0 x1
            gd y2 +- b 0 x1
            gd il */ x1 29289 100000
            gd ir +- r 0 il
            gd ib +- b 0 il
            ahXY gdRefX=adj minX=0 maxX=50000 x=x1 y=t
            cxn 3cd4 hc t
            cxn cd2 l vc
            cxn cd4 hc b
            cxn 0 r vc
            rect il il ir ib
            path
            M l x1
            A x1 x1 cd2 cd4
            L x2 t
            A x1 x1 3cd4 cd4
            L r y2
            A x1 x1 0 cd4
            L x1 b
            A x1 x1 cd4 cd4
            Z
            """,
        "rtTriangle": """
            gd it */ h 7 12
            gd ir */ w 7 12
            gd ib */ h 11 12
            gd wd12 */ w 1 12
            cxn 3cd4 l t
            cxn cd2 l vc
            cxn cd4 l b
            cxn cd4 hc b
            cxn cd4 r b
            cxn 0 hc vc
            rect wd12 it ir ib
            path
            M l b
            L l t
            L r b
            Z
            """,
        "smileyFace": """
            av adj val 4653
            gd a pin -4653 adj 4653
            gd x1 */ w 4969 21699
            gd x2 */ w 6215 21600
            gd x3 */ w 13135 21600
            gd x4 */ w 16640 21600
            gd y1 */ h 7570 21600
            gd y3 */ h 16515 21600
            gd dy2 */ h a 100000
            gd y2 +- y3 0 dy2
            gd y4 +- y3 dy2 0
            gd dy3 */ h a 50000
            gd y5 +- y4 dy3 0
            gd idx cos wd2 2700000
            gd idy sin hd2 2700000
            gd il +- hc 0 idx
            gd ir +- hc idx 0
            gd it +- vc 0 idy
            gd ib +- vc idy 0
            gd wR */ w 1125 21600
            gd hR */ h 1125 21600
            ahXY gdRefY=adj minY=-4653 maxY=4653 x=hc y=y4
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
            A wd2 hd2 cd2 21600000
            Z
            path fill=darkenLess extrusionOk=false
            M x2 y1
            A wR hR cd2 21600000
            M x3 y1
            A wR hR cd2 21600000
            path fill=none extrusionOk=false
            M x1 y2
            Q hc y5 x4 y2
            path fill=none
            M l vc
            A wd2 hd2 cd2 21600000
            Z
            """,
        "snip1Rect": """
            av adj val 16667
            gd a pin 0 adj 50000
            gd dx1 */ ss a 100000
            gd x1 +- r 0 dx1
            gd it */ dx1 1 2
            gd ir +/ x1 r 2
            ahXY gdRefX=adj minX=0 maxX=50000 x=x1 y=t
            cxn 0 r vc
            cxn cd4 hc b
            cxn cd2 l vc
            cxn 3cd4 hc t
            rect l it ir b
            path
            M l t
            L x1 t
            L r dx1
            L r b
            L l b
            Z
            """,
        "snip2DiagRect": """
            av adj1 val 0
            av adj2 val 16667
            gd a1 pin 0 adj1 50000
            gd a2 pin 0 adj2 50000
            gd lx1 */ ss a1 100000
            gd lx2 +- r 0 lx1
            gd ly1 +- b 0 lx1
            gd rx1 */ ss a2 100000
            gd rx2 +- r 0 rx1
            gd ry1 +- b 0 rx1
            gd d +- lx1 0 rx1
            gd dx ?: d lx1 rx1
            gd il */ dx 1 2
            gd ir +- r 0 il
            gd ib +- b 0 il
            ahXY gdRefX=adj1 minX=0 maxX=50000 x=lx1 y=t
            ahXY gdRefX=adj2 minX=0 maxX=50000 x=rx2 y=t
            cxn 0 r vc
            cxn cd4 hc b
            cxn cd2 l vc
            cxn 3cd4 hc t
            rect il il ir ib
            path
            M lx1 t
            L rx2 t
            L r rx1
            L r ly1
            L lx2 b
            L rx1 b
            L l ry1
            L l lx1
            Z
            """,
        "snip2SameRect": """
            av adj1 val 16667
            av adj2 val 0
            gd a1 pin 0 adj1 50000
            gd a2 pin 0 adj2 50000
            gd tx1 */ ss a1 100000
            gd tx2 +- r 0 tx1
            gd bx1 */ ss a2 100000
            gd bx2 +- r 0 bx1
            gd by1 +- b 0 bx1
            gd d +- tx1 0 bx1
            gd dx ?: d tx1 bx1
            gd il */ dx 1 2
            gd ir +- r 0 il
            gd it */ tx1 1 2
            gd ib +/ by1 b 2
            ahXY gdRefX=adj1 minX=0 maxX=50000 x=tx2 y=t
            ahXY gdRefX=adj2 minX=0 maxX=50000 x=bx1 y=b
            cxn 0 r vc
            cxn cd4 hc b
            cxn cd2 l vc
            cxn 3cd4 hc t
            rect il it ir ib
            path
            M tx1 t
            L tx2 t
            L r tx1
            L r by1
            L bx2 b
            L bx1 b
            L l by1
            L l tx1
            Z
            """,
        "snipRoundRect": """
            av adj1 val 16667
            av adj2 val 16667
            gd a1 pin 0 adj1 50000
            gd a2 pin 0 adj2 50000
            gd x1 */ ss a1 100000
            gd dx2 */ ss a2 100000
            gd x2 +- r 0 dx2
            gd il */ x1 29289 100000
            gd ir +/ x2 r 2
            ahXY gdRefX=adj1 minX=0 maxX=50000 x=x1 y=t
            ahXY gdRefX=adj2 minX=0 maxX=50000 x=x2 y=t
            cxn 0 r vc
            cxn cd4 hc b
            cxn cd2 l vc
            cxn 3cd4 hc t
            rect il il ir b
            path
            M x1 t
            L x2 t
            L r dx2
            L r b
            L l b
            L l x1
            A x1 x1 cd2 cd4
            Z
            """,
        "squareTabs": """
            gd md mod w h 0
            gd dx */ 1 md 20
            gd y1 +- 0 b dx
            gd x1 +- 0 r dx
            cxn cd2 l t
            cxn cd2 l dx
            cxn cd2 l y1
            cxn cd2 l b
            cxn cd2 dx dx
            cxn cd2 dx x1
            cxn 3cd4 dx t
            cxn 3cd4 x1 t
            cxn cd4 dx b
            cxn cd4 x1 b
            cxn 0 r t
            cxn 0 r dx
            cxn 0 r y1
            cxn 0 r b
            cxn 0 x1 dx
            cxn 0 x1 y1
            rect dx dx x1 y1
            path
            M l t
            L dx t
            L dx dx
            L l dx
            Z
            path
            M l y1
            L dx y1
            L dx b
            L l b
            Z
            path
            M x1 t
            L r t
            L r dx
            L x1 dx
            Z
            path
            M x1 y1
            L r y1
            L r b
            L x1 b
            Z
            """,
        "sun": """
            av adj val 25000
            gd a pin 12500 adj 46875
            gd g0 +- 50000 0 a
            gd g1 */ g0 30274 32768
            gd g2 */ g0 12540 32768
            gd g3 +- g1 50000 0
            gd g4 +- g2 50000 0
            gd g5 +- 50000 0 g1
            gd g6 +- 50000 0 g2
            gd g7 */ g0 23170 32768
            gd g8 +- 50000 g7 0
            gd g9 +- 50000 0 g7
            gd g10 */ g5 3 4
            gd g11 */ g6 3 4
            gd g12 +- g10 3662 0
            gd g13 +- g11 3662 0
            gd g14 +- g11 12500 0
            gd g15 +- 100000 0 g10
            gd g16 +- 100000 0 g12
            gd g17 +- 100000 0 g13
            gd g18 +- 100000 0 g14
            gd ox1 */ w 18436 21600
            gd oy1 */ h 3163 21600
            gd ox2 */ w 3163 21600
            gd oy2 */ h 18436 21600
            gd x8 */ w g8 100000
            gd x9 */ w g9 100000
            gd x10 */ w g10 100000
            gd x12 */ w g12 100000
            gd x13 */ w g13 100000
            gd x14 */ w g14 100000
            gd x15 */ w g15 100000
            gd x16 */ w g16 100000
            gd x17 */ w g17 100000
            gd x18 */ w g18 100000
            gd x19 */ w a 100000
            gd wR */ w g0 100000
            gd hR */ h g0 100000
            gd y8 */ h g8 100000
            gd y9 */ h g9 100000
            gd y10 */ h g10 100000
            gd y12 */ h g12 100000
            gd y13 */ h g13 100000
            gd y14 */ h g14 100000
            gd y15 */ h g15 100000
            gd y16 */ h g16 100000
            gd y17 */ h g17 100000
            gd y18 */ h g18 100000
            ahXY gdRefX=adj minX=12500 maxX=46875 x=x19 y=vc
            cxn 3cd4 hc t
            cxn cd2 l vc
            cxn cd4 hc b
            cxn 0 r vc
            rect x9 y9 x8 y8
            path
            M r vc
            L x15 y18
            L x15 y14
            Z
            M ox1 oy1
            L x16 y13
            L x17 y12
            Z
            M hc t
            L x18 y10
            L x14 y10
            Z
            M ox2 oy1
            L x13 y12
            L x12 y13
            Z
            M l vc
            L x10 y14
            L x10 y18
            Z
            M ox2 oy2
            L x12 y17
            L x13 y16
            Z
            M hc b
            L x14 y15
            L x18 y15
            Z
            M ox1 oy2
            L x17 y16
            L x16 y17
            Z
            M x19 vc
            A wR hR cd2 21600000
            Z
            """,
        "teardrop": """
            av adj val 100000
            gd a pin 0 adj 200000
            gd r2 sqrt 2
            gd tw */ wd2 r2 1
            gd th */ hd2 r2 1
            gd sw */ tw a 100000
            gd sh */ th a 100000
            gd dx1 cos sw 2700000
            gd dy1 sin sh 2700000
            gd x1 +- hc dx1 0
            gd y1 +- vc 0 dy1
            gd x2 +/ hc x1 2
            gd y2 +/ vc y1 2
            gd idx cos wd2 2700000
            gd idy sin hd2 2700000
            gd il +- hc 0 idx
            gd ir +- hc idx 0
            gd it +- vc 0 idy
            gd ib +- vc idy 0
            ahXY gdRefX=adj minX=0 maxX=200000 x=x1 y=t
            cxn 0 r vc
            cxn cd4 ir ib
            cxn cd4 hc b
            cxn cd4 il ib
            cxn cd2 l vc
            cxn 3cd4 il it
            cxn 3cd4 hc t
            cxn 3cd4 x1 y1
            rect il it ir ib
            path
            M l vc
            A wd2 hd2 cd2 cd4
            Q x2 t x1 y1
            Q r y2 r vc
            A wd2 hd2 0 cd4
            A wd2 hd2 cd4 cd4
            Z
            """,
        "trapezoid": """
            av adj val 25000
            gd maxAdj */ 50000 w ss
            gd a pin 0 adj maxAdj
            gd x1 */ ss a 200000
            gd x2 */ ss a 100000
            gd x3 +- r 0 x2
            gd x4 +- r 0 x1
            gd il */ wd3 a maxAdj
            gd it */ hd3 a maxAdj
            gd ir +- r 0 il
            ahXY gdRefX=adj minX=0 maxX=maxAdj x=x2 y=t
            cxn 3cd4 hc t
            cxn cd2 x1 vc
            cxn cd4 hc b
            cxn 0 x4 vc
            rect il it ir b
            path
            M l b
            L x2 t
            L x3 t
            L r b
            Z
            """,
        "triangle": """
            av adj val 50000
            gd a pin 0 adj 100000
            gd x1 */ w a 200000
            gd x2 */ w a 100000
            gd x3 +- x1 wd2 0
            ahXY gdRefX=adj minX=0 maxX=100000 x=x2 y=t
            cxn 3cd4 x2 t
            cxn cd2 x1 vc
            cxn cd4 l b
            cxn cd4 x2 b
            cxn cd4 r b
            cxn 0 x3 vc
            rect x1 vc x3 b
            path
            M l b
            L x2 t
            L r b
            Z
            """,
    ]
}
