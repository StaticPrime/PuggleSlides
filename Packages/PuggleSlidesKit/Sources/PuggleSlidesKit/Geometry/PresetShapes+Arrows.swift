// DrawingML preset shapes, transcribed from ECMA-376 Part 1's presetShapeDefinitions.xml. See PresetShapeDefinition
// for the statement syntax and the errata fixed.

extension PresetShapeSource {
    static let arrows: [String: String] = [
        "bentArrow": """
            av adj1 val 25000
            av adj2 val 25000
            av adj3 val 25000
            av adj4 val 43750
            gd a2 pin 0 adj2 50000
            gd maxAdj1 */ a2 2 1
            gd a1 pin 0 adj1 maxAdj1
            gd a3 pin 0 adj3 50000
            gd th */ ss a1 100000
            gd aw2 */ ss a2 100000
            gd th2 */ th 1 2
            gd dh2 +- aw2 0 th2
            gd ah */ ss a3 100000
            gd bw +- r 0 ah
            gd bh +- b 0 dh2
            gd bs min bw bh
            gd maxAdj4 */ 100000 bs ss
            gd a4 pin 0 adj4 maxAdj4
            gd bd */ ss a4 100000
            gd bd3 +- bd 0 th
            gd bd2 max bd3 0
            gd x3 +- th bd2 0
            gd x4 +- r 0 ah
            gd y3 +- dh2 th 0
            gd y4 +- y3 dh2 0
            gd y5 +- dh2 bd 0
            gd y6 +- y3 bd2 0
            ahXY gdRefX=adj1 minX=0 maxX=maxAdj1 x=th y=b
            ahXY gdRefY=adj2 minY=0 maxY=50000 x=r y=y4
            ahXY gdRefX=adj3 minX=0 maxX=50000 x=x4 y=t
            ahXY gdRefX=adj4 minX=0 maxX=maxAdj4 x=bd y=t
            cxn 3cd4 x4 t
            cxn cd4 x4 y4
            cxn cd4 th2 b
            cxn 0 r aw2
            rect l t r b
            path
            M l b
            L l y5
            A bd bd cd2 cd4
            L x4 dh2
            L x4 t
            L r aw2
            L x4 y4
            L x4 y3
            L x3 y3
            A bd2 bd2 3cd4 -5400000
            L th b
            Z
            """,
        "bentUpArrow": """
            av adj1 val 25000
            av adj2 val 25000
            av adj3 val 25000
            gd a1 pin 0 adj1 50000
            gd a2 pin 0 adj2 50000
            gd a3 pin 0 adj3 50000
            gd y1 */ ss a3 100000
            gd dx1 */ ss a2 50000
            gd x1 +- r 0 dx1
            gd dx3 */ ss a2 100000
            gd x3 +- r 0 dx3
            gd dx2 */ ss a1 200000
            gd x2 +- x3 0 dx2
            gd x4 +- x3 dx2 0
            gd dy2 */ ss a1 100000
            gd y2 +- b 0 dy2
            gd x0 */ x4 1 2
            gd y3 +/ y2 b 2
            gd y15 +/ y1 b 2
            ahXY gdRefY=adj1 minY=0 maxY=50000 x=l y=y2
            ahXY gdRefX=adj2 minX=0 maxX=50000 x=x1 y=t
            ahXY gdRefY=adj3 minY=0 maxY=50000 x=x2 y=y1
            cxn 3cd4 x3 t
            cxn cd2 x1 y1
            cxn cd2 l y3
            cxn cd4 x0 b
            cxn 0 x4 y15
            cxn 0 r y1
            rect l y2 x4 b
            path
            M l y2
            L x2 y2
            L x2 y1
            L x1 y1
            L x3 t
            L r y1
            L x4 y1
            L x4 b
            L l b
            Z
            """,
        "chevron": """
            av adj val 50000
            gd maxAdj */ 100000 w ss
            gd a pin 0 adj maxAdj
            gd x1 */ ss a 100000
            gd x2 +- r 0 x1
            gd x3 */ x2 1 2
            gd dx +- x2 0 x1
            gd il ?: dx x1 l
            gd ir ?: dx x2 r
            ahXY gdRefX=adj minX=0 maxX=maxAdj x=x2 y=t
            cxn 3cd4 x3 t
            cxn cd2 x1 vc
            cxn cd4 x3 b
            cxn 0 r vc
            rect il t ir b
            path
            M l t
            L x2 t
            L r vc
            L x2 b
            L l b
            L x1 vc
            Z
            """,
        "circularArrow": """
            av adj1 val 12500
            av adj2 val 1142319
            av adj3 val 20457681
            av adj4 val 10800000
            av adj5 val 12500
            gd a5 pin 0 adj5 25000
            gd maxAdj1 */ a5 2 1
            gd a1 pin 0 adj1 maxAdj1
            gd enAng pin 1 adj3 21599999
            gd stAng pin 0 adj4 21599999
            gd th */ ss a1 100000
            gd thh */ ss a5 100000
            gd th2 */ th 1 2
            gd rw1 +- wd2 th2 thh
            gd rh1 +- hd2 th2 thh
            gd rw2 +- rw1 0 th
            gd rh2 +- rh1 0 th
            gd rw3 +- rw2 th2 0
            gd rh3 +- rh2 th2 0
            gd wtH sin rw3 enAng
            gd htH cos rh3 enAng
            gd dxH cat2 rw3 htH wtH
            gd dyH sat2 rh3 htH wtH
            gd xH +- hc dxH 0
            gd yH +- vc dyH 0
            gd rI min rw2 rh2
            gd u1 */ dxH dxH 1
            gd u2 */ dyH dyH 1
            gd u3 */ rI rI 1
            gd u4 +- u1 0 u3
            gd u5 +- u2 0 u3
            gd u6 */ u4 u5 u1
            gd u7 */ u6 1 u2
            gd u8 +- 1 0 u7
            gd u9 sqrt u8
            gd u10 */ u4 1 dxH
            gd u11 */ u10 1 dyH
            gd u12 +/ 1 u9 u11
            gd u13 at2 1 u12
            gd u14 +- u13 21600000 0
            gd u15 ?: u13 u13 u14
            gd u16 +- u15 0 enAng
            gd u17 +- u16 21600000 0
            gd u18 ?: u16 u16 u17
            gd u19 +- u18 0 cd2
            gd u20 +- u18 0 21600000
            gd u21 ?: u19 u20 u18
            gd maxAng abs u21
            gd aAng pin 0 adj2 maxAng
            gd ptAng +- enAng aAng 0
            gd wtA sin rw3 ptAng
            gd htA cos rh3 ptAng
            gd dxA cat2 rw3 htA wtA
            gd dyA sat2 rh3 htA wtA
            gd xA +- hc dxA 0
            gd yA +- vc dyA 0
            gd wtE sin rw1 stAng
            gd htE cos rh1 stAng
            gd dxE cat2 rw1 htE wtE
            gd dyE sat2 rh1 htE wtE
            gd xE +- hc dxE 0
            gd yE +- vc dyE 0
            gd dxG cos thh ptAng
            gd dyG sin thh ptAng
            gd xG +- xH dxG 0
            gd yG +- yH dyG 0
            gd dxB cos thh ptAng
            gd dyB sin thh ptAng
            gd xB +- xH 0 dxB
            gd yB +- yH 0 dyB
            gd sx1 +- xB 0 hc
            gd sy1 +- yB 0 vc
            gd sx2 +- xG 0 hc
            gd sy2 +- yG 0 vc
            gd rO min rw1 rh1
            gd x1O */ sx1 rO rw1
            gd y1O */ sy1 rO rh1
            gd x2O */ sx2 rO rw1
            gd y2O */ sy2 rO rh1
            gd dxO +- x2O 0 x1O
            gd dyO +- y2O 0 y1O
            gd dO mod dxO dyO 0
            gd q1 */ x1O y2O 1
            gd q2 */ x2O y1O 1
            gd DO +- q1 0 q2
            gd q3 */ rO rO 1
            gd q4 */ dO dO 1
            gd q5 */ q3 q4 1
            gd q6 */ DO DO 1
            gd q7 +- q5 0 q6
            gd q8 max q7 0
            gd sdelO sqrt q8
            gd ndyO */ dyO -1 1
            gd sdyO ?: ndyO -1 1
            gd q9 */ sdyO dxO 1
            gd q10 */ q9 sdelO 1
            gd q11 */ DO dyO 1
            gd dxF1 +/ q11 q10 q4
            gd q12 +- q11 0 q10
            gd dxF2 */ q12 1 q4
            gd adyO abs dyO
            gd q13 */ adyO sdelO 1
            gd q14 */ DO dxO -1
            gd dyF1 +/ q14 q13 q4
            gd q15 +- q14 0 q13
            gd dyF2 */ q15 1 q4
            gd q16 +- x2O 0 dxF1
            gd q17 +- x2O 0 dxF2
            gd q18 +- y2O 0 dyF1
            gd q19 +- y2O 0 dyF2
            gd q20 mod q16 q18 0
            gd q21 mod q17 q19 0
            gd q22 +- q21 0 q20
            gd dxF ?: q22 dxF1 dxF2
            gd dyF ?: q22 dyF1 dyF2
            gd sdxF */ dxF rw1 rO
            gd sdyF */ dyF rh1 rO
            gd xF +- hc sdxF 0
            gd yF +- vc sdyF 0
            gd x1I */ sx1 rI rw2
            gd y1I */ sy1 rI rh2
            gd x2I */ sx2 rI rw2
            gd y2I */ sy2 rI rh2
            gd dxI +- x2I 0 x1I
            gd dyI +- y2I 0 y1I
            gd dI mod dxI dyI 0
            gd v1 */ x1I y2I 1
            gd v2 */ x2I y1I 1
            gd DI +- v1 0 v2
            gd v3 */ rI rI 1
            gd v4 */ dI dI 1
            gd v5 */ v3 v4 1
            gd v6 */ DI DI 1
            gd v7 +- v5 0 v6
            gd v8 max v7 0
            gd sdelI sqrt v8
            gd v9 */ sdyO dxI 1
            gd v10 */ v9 sdelI 1
            gd v11 */ DI dyI 1
            gd dxC1 +/ v11 v10 v4
            gd v12 +- v11 0 v10
            gd dxC2 */ v12 1 v4
            gd adyI abs dyI
            gd v13 */ adyI sdelI 1
            gd v14 */ DI dxI -1
            gd dyC1 +/ v14 v13 v4
            gd v15 +- v14 0 v13
            gd dyC2 */ v15 1 v4
            gd v16 +- x1I 0 dxC1
            gd v17 +- x1I 0 dxC2
            gd v18 +- y1I 0 dyC1
            gd v19 +- y1I 0 dyC2
            gd v20 mod v16 v18 0
            gd v21 mod v17 v19 0
            gd v22 +- v21 0 v20
            gd dxC ?: v22 dxC1 dxC2
            gd dyC ?: v22 dyC1 dyC2
            gd sdxC */ dxC rw2 rI
            gd sdyC */ dyC rh2 rI
            gd xC +- hc sdxC 0
            gd yC +- vc sdyC 0
            gd ist0 at2 sdxC sdyC
            gd ist1 +- ist0 21600000 0
            gd istAng ?: ist0 ist0 ist1
            gd isw1 +- stAng 0 istAng
            gd isw2 +- isw1 0 21600000
            gd iswAng ?: isw1 isw2 isw1
            gd p1 +- xF 0 xC
            gd p2 +- yF 0 yC
            gd p3 mod p1 p2 0
            gd p4 */ p3 1 2
            gd p5 +- p4 0 thh
            gd xGp ?: p5 xF xG
            gd yGp ?: p5 yF yG
            gd xBp ?: p5 xC xB
            gd yBp ?: p5 yC yB
            gd en0 at2 sdxF sdyF
            gd en1 +- en0 21600000 0
            gd en2 ?: en0 en0 en1
            gd sw0 +- en2 0 stAng
            gd sw1 +- sw0 21600000 0
            gd swAng ?: sw0 sw0 sw1
            gd wtI sin rw3 stAng
            gd htI cos rh3 stAng
            gd dxI cat2 rw3 htI wtI
            gd dyI sat2 rh3 htI wtI
            gd xI +- hc dxI 0
            gd yI +- vc dyI 0
            gd aI +- stAng 0 cd4
            gd aA +- ptAng cd4 0
            gd aB +- ptAng cd2 0
            gd idx cos rw1 2700000
            gd idy sin rh1 2700000
            gd il +- hc 0 idx
            gd ir +- hc idx 0
            gd it +- vc 0 idy
            gd ib +- vc idy 0
            ahPolar gdRefAng=adj2 minAng=0 maxAng=maxAng x=xA y=yA
            ahPolar gdRefAng=adj4 minAng=0 maxAng=21599999 x=xE y=yE
            ahPolar gdRefR=adj1 minR=0 maxR=maxAdj1 gdRefAng=adj3 minAng=0 maxAng=21599999 x=xF y=yF
            ahPolar gdRefR=adj5 minR=0 maxR=25000 x=xB y=yB
            cxn aI xI yI
            cxn ptAng xGp yGp
            cxn aA xA yA
            cxn aB xBp yBp
            rect il it ir ib
            path
            M xE yE
            A rw1 rh1 stAng swAng
            L xGp yGp
            L xA yA
            L xBp yBp
            L xC yC
            A rw2 rh2 istAng iswAng
            Z
            """,
        "curvedDownArrow": """
            av adj1 val 25000
            av adj2 val 50000
            av adj3 val 25000
            gd maxAdj2 */ 50000 w ss
            gd a2 pin 0 adj2 maxAdj2
            gd a1 pin 0 adj1 100000
            gd th */ ss a1 100000
            gd aw */ ss a2 100000
            gd q1 +/ th aw 4
            gd wR +- wd2 0 q1
            gd q7 */ wR 2 1
            gd q8 */ q7 q7 1
            gd q9 */ th th 1
            gd q10 +- q8 0 q9
            gd q11 sqrt q10
            gd idy */ q11 h q7
            gd maxAdj3 */ 100000 idy ss
            gd a3 pin 0 adj3 maxAdj3
            gd ah */ ss adj3 100000
            gd x3 +- wR th 0
            gd q2 */ h h 1
            gd q3 */ ah ah 1
            gd q4 +- q2 0 q3
            gd q5 sqrt q4
            gd dx */ q5 wR h
            gd x5 +- wR dx 0
            gd x7 +- x3 dx 0
            gd q6 +- aw 0 th
            gd dh */ q6 1 2
            gd x4 +- x5 0 dh
            gd x8 +- x7 dh 0
            gd aw2 */ aw 1 2
            gd x6 +- r 0 aw2
            gd y1 +- b 0 ah
            gd swAng at2 ah dx
            gd mswAng +- 0 0 swAng
            gd iy +- b 0 idy
            gd ix +/ wR x3 2
            gd q12 */ th 1 2
            gd dang2 at2 idy q12
            gd stAng +- 3cd4 swAng 0
            gd stAng2 +- 3cd4 0 dang2
            gd swAng2 +- dang2 0 cd4
            gd swAng3 +- cd4 dang2 0
            ahXY gdRefX=adj1 minX=0 maxX=adj2 x=x7 y=y1
            ahXY gdRefX=adj2 minX=0 maxX=maxAdj2 x=x4 y=b
            ahXY gdRefY=adj3 minY=0 maxY=maxAdj3 x=r y=y1
            cxn 3cd4 ix t
            cxn cd4 q12 b
            cxn cd4 x4 y1
            cxn cd4 x6 b
            cxn 0 x8 y1
            rect l t r b
            path stroke=false extrusionOk=false
            M x6 b
            L x4 y1
            L x5 y1
            A wR h stAng mswAng
            L x3 t
            A wR h 3cd4 swAng
            L x8 y1
            Z
            path fill=darkenLess stroke=false extrusionOk=false
            M ix iy
            A wR h stAng2 swAng2
            L l b
            A wR h cd2 swAng3
            Z
            path fill=none extrusionOk=false
            M ix iy
            A wR h stAng2 swAng2
            L l b
            A wR h cd2 cd4
            L x3 t
            A wR h 3cd4 swAng
            L x8 y1
            L x6 b
            L x4 y1
            L x5 y1
            A wR h stAng mswAng
            """,
        "curvedLeftArrow": """
            av adj1 val 25000
            av adj2 val 50000
            av adj3 val 25000
            gd maxAdj2 */ 50000 h ss
            gd a2 pin 0 adj2 maxAdj2
            gd a1 pin 0 adj1 a2
            gd th */ ss a1 100000
            gd aw */ ss a2 100000
            gd q1 +/ th aw 4
            gd hR +- hd2 0 q1
            gd q7 */ hR 2 1
            gd q8 */ q7 q7 1
            gd q9 */ th th 1
            gd q10 +- q8 0 q9
            gd q11 sqrt q10
            gd idx */ q11 w q7
            gd maxAdj3 */ 100000 idx ss
            gd a3 pin 0 adj3 maxAdj3
            gd ah */ ss a3 100000
            gd y3 +- hR th 0
            gd q2 */ w w 1
            gd q3 */ ah ah 1
            gd q4 +- q2 0 q3
            gd q5 sqrt q4
            gd dy */ q5 hR w
            gd y5 +- hR dy 0
            gd y7 +- y3 dy 0
            gd q6 +- aw 0 th
            gd dh */ q6 1 2
            gd y4 +- y5 0 dh
            gd y8 +- y7 dh 0
            gd aw2 */ aw 1 2
            gd y6 +- b 0 aw2
            gd x1 +- l ah 0
            gd swAng at2 ah dy
            gd mswAng +- 0 0 swAng
            gd ix +- l idx 0
            gd iy +/ hR y3 2
            gd q12 */ th 1 2
            gd dang2 at2 idx q12
            gd swAng2 +- dang2 0 swAng
            gd swAng3 +- swAng dang2 0
            gd stAng3 +- 0 0 dang2
            ahXY gdRefY=adj1 minY=0 maxY=a2 x=x1 y=y5
            ahXY gdRefY=adj2 minY=0 maxY=maxAdj2 x=r y=y4
            ahXY gdRefX=adj3 minX=0 maxX=maxAdj3 x=x1 y=b
            cxn cd2 l q12
            cxn cd2 x1 y4
            cxn cd2 l y6
            cxn cd4 x1 y8
            cxn 0 r iy
            rect l t r b
            path stroke=false extrusionOk=false
            M l y6
            L x1 y4
            L x1 y5
            A w hR swAng swAng2
            A w hR stAng3 swAng3
            L x1 y8
            Z
            path fill=darkenLess stroke=false extrusionOk=false
            M r y3
            A w hR 0 -5400000
            L l t
            A w hR 3cd4 cd4
            Z
            path fill=none extrusionOk=false
            M r y3
            A w hR 0 -5400000
            L l t
            A w hR 3cd4 cd4
            L r y3
            A w hR 0 swAng
            L x1 y8
            L l y6
            L x1 y4
            L x1 y5
            A w hR swAng swAng2
            """,
        "curvedRightArrow": """
            av adj1 val 25000
            av adj2 val 50000
            av adj3 val 25000
            gd maxAdj2 */ 50000 h ss
            gd a2 pin 0 adj2 maxAdj2
            gd a1 pin 0 adj1 a2
            gd th */ ss a1 100000
            gd aw */ ss a2 100000
            gd q1 +/ th aw 4
            gd hR +- hd2 0 q1
            gd q7 */ hR 2 1
            gd q8 */ q7 q7 1
            gd q9 */ th th 1
            gd q10 +- q8 0 q9
            gd q11 sqrt q10
            gd idx */ q11 w q7
            gd maxAdj3 */ 100000 idx ss
            gd a3 pin 0 adj3 maxAdj3
            gd ah */ ss a3 100000
            gd y3 +- hR th 0
            gd q2 */ w w 1
            gd q3 */ ah ah 1
            gd q4 +- q2 0 q3
            gd q5 sqrt q4
            gd dy */ q5 hR w
            gd y5 +- hR dy 0
            gd y7 +- y3 dy 0
            gd q6 +- aw 0 th
            gd dh */ q6 1 2
            gd y4 +- y5 0 dh
            gd y8 +- y7 dh 0
            gd aw2 */ aw 1 2
            gd y6 +- b 0 aw2
            gd x1 +- r 0 ah
            gd swAng at2 ah dy
            gd stAng +- cd2 0 swAng
            gd mswAng +- 0 0 swAng
            gd ix +- r 0 idx
            gd iy +/ hR y3 2
            gd q12 */ th 1 2
            gd dang2 at2 idx q12
            gd swAng2 +- dang2 0 cd4
            gd swAng3 +- cd4 dang2 0
            gd stAng3 +- cd2 0 dang2
            ahXY gdRefY=adj1 minY=0 maxY=a2 x=x1 y=y5
            ahXY gdRefY=adj2 minY=0 maxY=maxAdj2 x=r y=y4
            ahXY gdRefX=adj3 minX=0 maxX=maxAdj3 x=x1 y=b
            cxn cd2 l iy
            cxn cd4 x1 y8
            cxn 0 r y6
            cxn 0 x1 y4
            cxn 0 r q12
            rect l t r b
            path stroke=false extrusionOk=false
            M l hR
            A w hR cd2 mswAng
            L x1 y4
            L r y6
            L x1 y8
            L x1 y7
            A w hR stAng swAng
            Z
            path fill=darkenLess stroke=false extrusionOk=false
            M r th
            A w hR 3cd4 swAng2
            A w hR stAng3 swAng3
            Z
            path fill=none extrusionOk=false
            M l hR
            A w hR cd2 mswAng
            L x1 y4
            L r y6
            L x1 y8
            L x1 y7
            A w hR stAng swAng
            L l hR
            A w hR cd2 cd4
            L r th
            A w hR 3cd4 swAng2
            """,
        "curvedUpArrow": """
            av adj1 val 25000
            av adj2 val 50000
            av adj3 val 25000
            gd maxAdj2 */ 50000 w ss
            gd a2 pin 0 adj2 maxAdj2
            gd a1 pin 0 adj1 100000
            gd th */ ss a1 100000
            gd aw */ ss a2 100000
            gd q1 +/ th aw 4
            gd wR +- wd2 0 q1
            gd q7 */ wR 2 1
            gd q8 */ q7 q7 1
            gd q9 */ th th 1
            gd q10 +- q8 0 q9
            gd q11 sqrt q10
            gd idy */ q11 h q7
            gd maxAdj3 */ 100000 idy ss
            gd a3 pin 0 adj3 maxAdj3
            gd ah */ ss adj3 100000
            gd x3 +- wR th 0
            gd q2 */ h h 1
            gd q3 */ ah ah 1
            gd q4 +- q2 0 q3
            gd q5 sqrt q4
            gd dx */ q5 wR h
            gd x5 +- wR dx 0
            gd x7 +- x3 dx 0
            gd q6 +- aw 0 th
            gd dh */ q6 1 2
            gd x4 +- x5 0 dh
            gd x8 +- x7 dh 0
            gd aw2 */ aw 1 2
            gd x6 +- r 0 aw2
            gd y1 +- t ah 0
            gd swAng at2 ah dx
            gd mswAng +- 0 0 swAng
            gd iy +- t idy 0
            gd ix +/ wR x3 2
            gd q12 */ th 1 2
            gd dang2 at2 idy q12
            gd swAng2 +- dang2 0 swAng
            gd mswAng2 +- 0 0 swAng2
            gd stAng3 +- cd4 0 swAng
            gd swAng3 +- swAng dang2 0
            gd stAng2 +- cd4 0 dang2
            ahXY gdRefX=adj1 minX=0 maxX=a2 x=x7 y=y1
            ahXY gdRefX=adj2 minX=0 maxX=maxAdj2 x=x4 y=t
            ahXY gdRefY=adj3 minY=0 maxY=maxAdj3 x=r y=y1
            cxn 3cd4 x6 t
            cxn 3cd4 x4 y1
            cxn 3cd4 q12 t
            cxn cd4 ix b
            cxn 0 x8 y1
            rect l t r b
            path stroke=false extrusionOk=false
            M x6 t
            L x8 y1
            L x7 y1
            A wR h stAng3 swAng3
            A wR h stAng2 swAng2
            L x4 y1
            Z
            path fill=darkenLess stroke=false extrusionOk=false
            M wR b
            A wR h cd4 cd4
            L th t
            A wR h cd2 -5400000
            Z
            path fill=none extrusionOk=false
            M ix iy
            A wR h stAng2 swAng2
            L x4 y1
            L x6 t
            L x8 y1
            L x7 y1
            A wR h stAng3 swAng
            L wR b
            A wR h cd4 cd4
            L th t
            A wR h cd2 -5400000
            """,
        "downArrow": """
            av adj1 val 50000
            av adj2 val 50000
            gd maxAdj2 */ 100000 h ss
            gd a1 pin 0 adj1 100000
            gd a2 pin 0 adj2 maxAdj2
            gd dy1 */ ss a2 100000
            gd y1 +- b 0 dy1
            gd dx1 */ w a1 200000
            gd x1 +- hc 0 dx1
            gd x2 +- hc dx1 0
            gd dy2 */ x1 dy1 wd2
            gd y2 +- y1 dy2 0
            ahXY gdRefX=adj1 minX=0 maxX=100000 x=x1 y=t
            ahXY gdRefY=adj2 minY=0 maxY=maxAdj2 x=l y=y1
            cxn 3cd4 hc t
            cxn cd2 l y1
            cxn cd4 hc b
            cxn 0 r y1
            rect x1 t x2 y2
            path
            M l y1
            L x1 y1
            L x1 t
            L x2 t
            L x2 y1
            L r y1
            L hc b
            Z
            """,
        "homePlate": """
            av adj val 50000
            gd maxAdj */ 100000 w ss
            gd a pin 0 adj maxAdj
            gd dx1 */ ss a 100000
            gd x1 +- r 0 dx1
            gd ir +/ x1 r 2
            gd x2 */ x1 1 2
            ahXY gdRefX=adj minX=0 maxX=maxAdj x=x1 y=t
            cxn 3cd4 x2 t
            cxn cd2 l vc
            cxn cd4 x1 b
            cxn 0 r vc
            rect l t ir b
            path
            M l t
            L x1 t
            L r vc
            L x1 b
            L l b
            Z
            """,
        "leftArrow": """
            av adj1 val 50000
            av adj2 val 50000
            gd maxAdj2 */ 100000 w ss
            gd a1 pin 0 adj1 100000
            gd a2 pin 0 adj2 maxAdj2
            gd dx2 */ ss a2 100000
            gd x2 +- l dx2 0
            gd dy1 */ h a1 200000
            gd y1 +- vc 0 dy1
            gd y2 +- vc dy1 0
            gd dx1 */ y1 dx2 hd2
            gd x1 +- x2 0 dx1
            ahXY gdRefY=adj1 minY=0 maxY=100000 x=r y=y1
            ahXY gdRefX=adj2 minX=0 maxX=maxAdj2 x=x2 y=t
            cxn 3cd4 x2 t
            cxn cd2 l vc
            cxn cd4 x2 b
            cxn 0 r vc
            rect x1 y1 r y2
            path
            M l vc
            L x2 t
            L x2 y1
            L r y1
            L r y2
            L x2 y2
            L x2 b
            Z
            """,
        "leftCircularArrow": """
            av adj1 val 12500
            av adj2 val -1142319
            av adj3 val 1142319
            av adj4 val 10800000
            av adj5 val 12500
            gd a5 pin 0 adj5 25000
            gd maxAdj1 */ a5 2 1
            gd a1 pin 0 adj1 maxAdj1
            gd enAng pin 1 adj3 21599999
            gd stAng pin 0 adj4 21599999
            gd th */ ss a1 100000
            gd thh */ ss a5 100000
            gd th2 */ th 1 2
            gd rw1 +- wd2 th2 thh
            gd rh1 +- hd2 th2 thh
            gd rw2 +- rw1 0 th
            gd rh2 +- rh1 0 th
            gd rw3 +- rw2 th2 0
            gd rh3 +- rh2 th2 0
            gd wtH sin rw3 enAng
            gd htH cos rh3 enAng
            gd dxH cat2 rw3 htH wtH
            gd dyH sat2 rh3 htH wtH
            gd xH +- hc dxH 0
            gd yH +- vc dyH 0
            gd rI min rw2 rh2
            gd u1 */ dxH dxH 1
            gd u2 */ dyH dyH 1
            gd u3 */ rI rI 1
            gd u4 +- u1 0 u3
            gd u5 +- u2 0 u3
            gd u6 */ u4 u5 u1
            gd u7 */ u6 1 u2
            gd u8 +- 1 0 u7
            gd u9 sqrt u8
            gd u10 */ u4 1 dxH
            gd u11 */ u10 1 dyH
            gd u12 +/ 1 u9 u11
            gd u13 at2 1 u12
            gd u14 +- u13 21600000 0
            gd u15 ?: u13 u13 u14
            gd u16 +- u15 0 enAng
            gd u17 +- u16 21600000 0
            gd u18 ?: u16 u16 u17
            gd u19 +- u18 0 cd2
            gd u20 +- u18 0 21600000
            gd u21 ?: u19 u20 u18
            gd u22 abs u21
            gd minAng */ u22 -1 1
            gd u23 abs adj2
            gd a2 */ u23 -1 1
            gd aAng pin minAng a2 0
            gd ptAng +- enAng aAng 0
            gd wtA sin rw3 ptAng
            gd htA cos rh3 ptAng
            gd dxA cat2 rw3 htA wtA
            gd dyA sat2 rh3 htA wtA
            gd xA +- hc dxA 0
            gd yA +- vc dyA 0
            gd wtE sin rw1 stAng
            gd htE cos rh1 stAng
            gd dxE cat2 rw1 htE wtE
            gd dyE sat2 rh1 htE wtE
            gd xE +- hc dxE 0
            gd yE +- vc dyE 0
            gd wtD sin rw2 stAng
            gd htD cos rh2 stAng
            gd dxD cat2 rw2 htD wtD
            gd dyD sat2 rh2 htD wtD
            gd xD +- hc dxD 0
            gd yD +- vc dyD 0
            gd dxG cos thh ptAng
            gd dyG sin thh ptAng
            gd xG +- xH dxG 0
            gd yG +- yH dyG 0
            gd dxB cos thh ptAng
            gd dyB sin thh ptAng
            gd xB +- xH 0 dxB
            gd yB +- yH 0 dyB
            gd sx1 +- xB 0 hc
            gd sy1 +- yB 0 vc
            gd sx2 +- xG 0 hc
            gd sy2 +- yG 0 vc
            gd rO min rw1 rh1
            gd x1O */ sx1 rO rw1
            gd y1O */ sy1 rO rh1
            gd x2O */ sx2 rO rw1
            gd y2O */ sy2 rO rh1
            gd dxO +- x2O 0 x1O
            gd dyO +- y2O 0 y1O
            gd dO mod dxO dyO 0
            gd q1 */ x1O y2O 1
            gd q2 */ x2O y1O 1
            gd DO +- q1 0 q2
            gd q3 */ rO rO 1
            gd q4 */ dO dO 1
            gd q5 */ q3 q4 1
            gd q6 */ DO DO 1
            gd q7 +- q5 0 q6
            gd q8 max q7 0
            gd sdelO sqrt q8
            gd ndyO */ dyO -1 1
            gd sdyO ?: ndyO -1 1
            gd q9 */ sdyO dxO 1
            gd q10 */ q9 sdelO 1
            gd q11 */ DO dyO 1
            gd dxF1 +/ q11 q10 q4
            gd q12 +- q11 0 q10
            gd dxF2 */ q12 1 q4
            gd adyO abs dyO
            gd q13 */ adyO sdelO 1
            gd q14 */ DO dxO -1
            gd dyF1 +/ q14 q13 q4
            gd q15 +- q14 0 q13
            gd dyF2 */ q15 1 q4
            gd q16 +- x2O 0 dxF1
            gd q17 +- x2O 0 dxF2
            gd q18 +- y2O 0 dyF1
            gd q19 +- y2O 0 dyF2
            gd q20 mod q16 q18 0
            gd q21 mod q17 q19 0
            gd q22 +- q21 0 q20
            gd dxF ?: q22 dxF1 dxF2
            gd dyF ?: q22 dyF1 dyF2
            gd sdxF */ dxF rw1 rO
            gd sdyF */ dyF rh1 rO
            gd xF +- hc sdxF 0
            gd yF +- vc sdyF 0
            gd x1I */ sx1 rI rw2
            gd y1I */ sy1 rI rh2
            gd x2I */ sx2 rI rw2
            gd y2I */ sy2 rI rh2
            gd dxI +- x2I 0 x1I
            gd dyI +- y2I 0 y1I
            gd dI mod dxI dyI 0
            gd v1 */ x1I y2I 1
            gd v2 */ x2I y1I 1
            gd DI +- v1 0 v2
            gd v3 */ rI rI 1
            gd v4 */ dI dI 1
            gd v5 */ v3 v4 1
            gd v6 */ DI DI 1
            gd v7 +- v5 0 v6
            gd v8 max v7 0
            gd sdelI sqrt v8
            gd v9 */ sdyO dxI 1
            gd v10 */ v9 sdelI 1
            gd v11 */ DI dyI 1
            gd dxC1 +/ v11 v10 v4
            gd v12 +- v11 0 v10
            gd dxC2 */ v12 1 v4
            gd adyI abs dyI
            gd v13 */ adyI sdelI 1
            gd v14 */ DI dxI -1
            gd dyC1 +/ v14 v13 v4
            gd v15 +- v14 0 v13
            gd dyC2 */ v15 1 v4
            gd v16 +- x1I 0 dxC1
            gd v17 +- x1I 0 dxC2
            gd v18 +- y1I 0 dyC1
            gd v19 +- y1I 0 dyC2
            gd v20 mod v16 v18 0
            gd v21 mod v17 v19 0
            gd v22 +- v21 0 v20
            gd dxC ?: v22 dxC1 dxC2
            gd dyC ?: v22 dyC1 dyC2
            gd sdxC */ dxC rw2 rI
            gd sdyC */ dyC rh2 rI
            gd xC +- hc sdxC 0
            gd yC +- vc sdyC 0
            gd ist0 at2 sdxC sdyC
            gd ist1 +- ist0 21600000 0
            gd istAng0 ?: ist0 ist0 ist1
            gd isw1 +- stAng 0 istAng0
            gd isw2 +- isw1 21600000 0
            gd iswAng0 ?: isw1 isw1 isw2
            gd istAng +- istAng0 iswAng0 0
            gd iswAng +- 0 0 iswAng0
            gd p1 +- xF 0 xC
            gd p2 +- yF 0 yC
            gd p3 mod p1 p2 0
            gd p4 */ p3 1 2
            gd p5 +- p4 0 thh
            gd xGp ?: p5 xF xG
            gd yGp ?: p5 yF yG
            gd xBp ?: p5 xC xB
            gd yBp ?: p5 yC yB
            gd en0 at2 sdxF sdyF
            gd en1 +- en0 21600000 0
            gd en2 ?: en0 en0 en1
            gd sw0 +- en2 0 stAng
            gd sw1 +- sw0 0 21600000
            gd swAng ?: sw0 sw1 sw0
            gd stAng0 +- stAng swAng 0
            gd swAng0 +- 0 0 swAng
            gd wtI sin rw3 stAng
            gd htI cos rh3 stAng
            gd dxI cat2 rw3 htI wtI
            gd dyI sat2 rh3 htI wtI
            gd xI +- hc dxI 0
            gd yI +- vc dyI 0
            gd aI +- stAng cd4 0
            gd aA +- ptAng 0 cd4
            gd aB +- ptAng cd2 0
            gd idx cos rw1 2700000
            gd idy sin rh1 2700000
            gd il +- hc 0 idx
            gd ir +- hc idx 0
            gd it +- vc 0 idy
            gd ib +- vc idy 0
            ahPolar gdRefAng=adj2 minAng=minAng maxAng=0 x=xA y=yA
            ahPolar gdRefAng=adj4 minAng=0 maxAng=21599999 x=xE y=yE
            ahPolar gdRefR=adj1 minR=0 maxR=maxAdj1 gdRefAng=adj3 minAng=0 maxAng=21599999 x=xF y=yF
            ahPolar gdRefR=adj5 minR=0 maxR=25000 x=xB y=yB
            cxn aI xI yI
            cxn ptAng xGp yGp
            cxn aA xA yA
            cxn aB xBp yBp
            rect il it ir ib
            path
            M xE yE
            L xD yD
            A rw2 rh2 istAng iswAng
            L xBp yBp
            L xA yA
            L xGp yGp
            L xF yF
            A rw1 rh1 stAng0 swAng0
            Z
            """,
        "leftRightArrow": """
            av adj1 val 50000
            av adj2 val 50000
            gd maxAdj2 */ 50000 w ss
            gd a1 pin 0 adj1 100000
            gd a2 pin 0 adj2 maxAdj2
            gd x2 */ ss a2 100000
            gd x3 +- r 0 x2
            gd dy */ h a1 200000
            gd y1 +- vc 0 dy
            gd y2 +- vc dy 0
            gd dx1 */ y1 x2 hd2
            gd x1 +- x2 0 dx1
            gd x4 +- x3 dx1 0
            ahXY gdRefY=adj1 minY=0 maxY=100000 x=x3 y=y1
            ahXY gdRefX=adj2 minX=0 maxX=maxAdj2 x=x2 y=t
            cxn 0 r vc
            cxn cd4 x3 b
            cxn cd4 x2 b
            cxn cd2 l vc
            cxn 3cd4 x2 t
            cxn 3cd4 x3 t
            rect x1 y1 x4 y2
            path
            M l vc
            L x2 t
            L x2 y1
            L x3 y1
            L x3 t
            L r vc
            L x3 b
            L x3 y2
            L x2 y2
            L x2 b
            Z
            """,
        "leftRightCircularArrow": """
            av adj1 val 12500
            av adj2 val 1142319
            av adj3 val 20457681
            av adj4 val 11942319
            av adj5 val 12500
            gd a5 pin 0 adj5 25000
            gd maxAdj1 */ a5 2 1
            gd a1 pin 0 adj1 maxAdj1
            gd enAng pin 1 adj3 21599999
            gd stAng pin 0 adj4 21599999
            gd th */ ss a1 100000
            gd thh */ ss a5 100000
            gd th2 */ th 1 2
            gd rw1 +- wd2 th2 thh
            gd rh1 +- hd2 th2 thh
            gd rw2 +- rw1 0 th
            gd rh2 +- rh1 0 th
            gd rw3 +- rw2 th2 0
            gd rh3 +- rh2 th2 0
            gd wtH sin rw3 enAng
            gd htH cos rh3 enAng
            gd dxH cat2 rw3 htH wtH
            gd dyH sat2 rh3 htH wtH
            gd xH +- hc dxH 0
            gd yH +- vc dyH 0
            gd rI min rw2 rh2
            gd u1 */ dxH dxH 1
            gd u2 */ dyH dyH 1
            gd u3 */ rI rI 1
            gd u4 +- u1 0 u3
            gd u5 +- u2 0 u3
            gd u6 */ u4 u5 u1
            gd u7 */ u6 1 u2
            gd u8 +- 1 0 u7
            gd u9 sqrt u8
            gd u10 */ u4 1 dxH
            gd u11 */ u10 1 dyH
            gd u12 +/ 1 u9 u11
            gd u13 at2 1 u12
            gd u14 +- u13 21600000 0
            gd u15 ?: u13 u13 u14
            gd u16 +- u15 0 enAng
            gd u17 +- u16 21600000 0
            gd u18 ?: u16 u16 u17
            gd u19 +- u18 0 cd2
            gd u20 +- u18 0 21600000
            gd u21 ?: u19 u20 u18
            gd maxAng abs u21
            gd aAng pin 0 adj2 maxAng
            gd ptAng +- enAng aAng 0
            gd wtA sin rw3 ptAng
            gd htA cos rh3 ptAng
            gd dxA cat2 rw3 htA wtA
            gd dyA sat2 rh3 htA wtA
            gd xA +- hc dxA 0
            gd yA +- vc dyA 0
            gd dxG cos thh ptAng
            gd dyG sin thh ptAng
            gd xG +- xH dxG 0
            gd yG +- yH dyG 0
            gd dxB cos thh ptAng
            gd dyB sin thh ptAng
            gd xB +- xH 0 dxB
            gd yB +- yH 0 dyB
            gd sx1 +- xB 0 hc
            gd sy1 +- yB 0 vc
            gd sx2 +- xG 0 hc
            gd sy2 +- yG 0 vc
            gd rO min rw1 rh1
            gd x1O */ sx1 rO rw1
            gd y1O */ sy1 rO rh1
            gd x2O */ sx2 rO rw1
            gd y2O */ sy2 rO rh1
            gd dxO +- x2O 0 x1O
            gd dyO +- y2O 0 y1O
            gd dO mod dxO dyO 0
            gd q1 */ x1O y2O 1
            gd q2 */ x2O y1O 1
            gd DO +- q1 0 q2
            gd q3 */ rO rO 1
            gd q4 */ dO dO 1
            gd q5 */ q3 q4 1
            gd q6 */ DO DO 1
            gd q7 +- q5 0 q6
            gd q8 max q7 0
            gd sdelO sqrt q8
            gd ndyO */ dyO -1 1
            gd sdyO ?: ndyO -1 1
            gd q9 */ sdyO dxO 1
            gd q10 */ q9 sdelO 1
            gd q11 */ DO dyO 1
            gd dxF1 +/ q11 q10 q4
            gd q12 +- q11 0 q10
            gd dxF2 */ q12 1 q4
            gd adyO abs dyO
            gd q13 */ adyO sdelO 1
            gd q14 */ DO dxO -1
            gd dyF1 +/ q14 q13 q4
            gd q15 +- q14 0 q13
            gd dyF2 */ q15 1 q4
            gd q16 +- x2O 0 dxF1
            gd q17 +- x2O 0 dxF2
            gd q18 +- y2O 0 dyF1
            gd q19 +- y2O 0 dyF2
            gd q20 mod q16 q18 0
            gd q21 mod q17 q19 0
            gd q22 +- q21 0 q20
            gd dxF ?: q22 dxF1 dxF2
            gd dyF ?: q22 dyF1 dyF2
            gd sdxF */ dxF rw1 rO
            gd sdyF */ dyF rh1 rO
            gd xF +- hc sdxF 0
            gd yF +- vc sdyF 0
            gd x1I */ sx1 rI rw2
            gd y1I */ sy1 rI rh2
            gd x2I */ sx2 rI rw2
            gd y2I */ sy2 rI rh2
            gd dxI +- x2I 0 x1I
            gd dyI +- y2I 0 y1I
            gd dI mod dxI dyI 0
            gd v1 */ x1I y2I 1
            gd v2 */ x2I y1I 1
            gd DI +- v1 0 v2
            gd v3 */ rI rI 1
            gd v4 */ dI dI 1
            gd v5 */ v3 v4 1
            gd v6 */ DI DI 1
            gd v7 +- v5 0 v6
            gd v8 max v7 0
            gd sdelI sqrt v8
            gd v9 */ sdyO dxI 1
            gd v10 */ v9 sdelI 1
            gd v11 */ DI dyI 1
            gd dxC1 +/ v11 v10 v4
            gd v12 +- v11 0 v10
            gd dxC2 */ v12 1 v4
            gd adyI abs dyI
            gd v13 */ adyI sdelI 1
            gd v14 */ DI dxI -1
            gd dyC1 +/ v14 v13 v4
            gd v15 +- v14 0 v13
            gd dyC2 */ v15 1 v4
            gd v16 +- x1I 0 dxC1
            gd v17 +- x1I 0 dxC2
            gd v18 +- y1I 0 dyC1
            gd v19 +- y1I 0 dyC2
            gd v20 mod v16 v18 0
            gd v21 mod v17 v19 0
            gd v22 +- v21 0 v20
            gd dxC ?: v22 dxC1 dxC2
            gd dyC ?: v22 dyC1 dyC2
            gd sdxC */ dxC rw2 rI
            gd sdyC */ dyC rh2 rI
            gd xC +- hc sdxC 0
            gd yC +- vc sdyC 0
            gd wtI sin rw3 stAng
            gd htI cos rh3 stAng
            gd dxI cat2 rw3 htI wtI
            gd dyI sat2 rh3 htI wtI
            gd xI +- hc dxI 0
            gd yI +- vc dyI 0
            gd lptAng +- stAng 0 aAng
            gd wtL sin rw3 lptAng
            gd htL cos rh3 lptAng
            gd dxL cat2 rw3 htL wtL
            gd dyL sat2 rh3 htL wtL
            gd xL +- hc dxL 0
            gd yL +- vc dyL 0
            gd dxK cos thh lptAng
            gd dyK sin thh lptAng
            gd xK +- xI dxK 0
            gd yK +- yI dyK 0
            gd dxJ cos thh lptAng
            gd dyJ sin thh lptAng
            gd xJ +- xI 0 dxJ
            gd yJ +- yI 0 dyJ
            gd p1 +- xF 0 xC
            gd p2 +- yF 0 yC
            gd p3 mod p1 p2 0
            gd p4 */ p3 1 2
            gd p5 +- p4 0 thh
            gd xGp ?: p5 xF xG
            gd yGp ?: p5 yF yG
            gd xBp ?: p5 xC xB
            gd yBp ?: p5 yC yB
            gd en0 at2 sdxF sdyF
            gd en1 +- en0 21600000 0
            gd en2 ?: en0 en0 en1
            gd od0 +- en2 0 enAng
            gd od1 +- od0 21600000 0
            gd od2 ?: od0 od0 od1
            gd st0 +- stAng 0 od2
            gd st1 +- st0 21600000 0
            gd st2 ?: st0 st0 st1
            gd sw0 +- en2 0 st2
            gd sw1 +- sw0 21600000 0
            gd swAng ?: sw0 sw0 sw1
            gd ist0 at2 sdxC sdyC
            gd ist1 +- ist0 21600000 0
            gd istAng ?: ist0 ist0 ist1
            gd id0 +- istAng 0 enAng
            gd id1 +- id0 0 21600000
            gd id2 ?: id0 id1 id0
            gd ien0 +- stAng 0 id2
            gd ien1 +- ien0 0 21600000
            gd ien2 ?: ien1 ien1 ien0
            gd isw1 +- ien2 0 istAng
            gd isw2 +- isw1 0 21600000
            gd iswAng ?: isw1 isw2 isw1
            gd wtE sin rw1 st2
            gd htE cos rh1 st2
            gd dxE cat2 rw1 htE wtE
            gd dyE sat2 rh1 htE wtE
            gd xE +- hc dxE 0
            gd yE +- vc dyE 0
            gd wtD sin rw2 ien2
            gd htD cos rh2 ien2
            gd dxD cat2 rw2 htD wtD
            gd dyD sat2 rh2 htD wtD
            gd xD +- hc dxD 0
            gd yD +- vc dyD 0
            gd xKp ?: p5 xE xK
            gd yKp ?: p5 yE yK
            gd xJp ?: p5 xD xJ
            gd yJp ?: p5 yD yJ
            gd aL +- lptAng 0 cd4
            gd aA +- ptAng cd4 0
            gd aB +- ptAng cd2 0
            gd aJ +- lptAng cd2 0
            gd idx cos rw1 2700000
            gd idy sin rh1 2700000
            gd il +- hc 0 idx
            gd ir +- hc idx 0
            gd it +- vc 0 idy
            gd ib +- vc idy 0
            ahPolar gdRefAng=adj2 minAng=0 maxAng=maxAng x=xA y=yA
            ahPolar gdRefAng=adj4 minAng=0 maxAng=21599999 x=xE y=yE
            ahPolar gdRefR=adj1 minR=0 maxR=maxAdj1 gdRefAng=adj3 minAng=0 maxAng=21599999 x=xF y=yF
            ahPolar gdRefR=adj5 minR=0 maxR=25000 x=xB y=yB
            cxn aL xL yL
            cxn lptAng xKp yKp
            cxn ptAng xGp yGp
            cxn aA xA yA
            cxn aB xBp yBp
            cxn aJ xJp yJp
            rect il it ir ib
            path
            M xL yL
            L xKp yKp
            L xE yE
            A rw1 rh1 st2 swAng
            L xGp yGp
            L xA yA
            L xBp yBp
            L xC yC
            A rw2 rh2 istAng iswAng
            L xJp yJp
            Z
            """,
        "leftRightUpArrow": """
            av adj1 val 25000
            av adj2 val 25000
            av adj3 val 25000
            gd a2 pin 0 adj2 50000
            gd maxAdj1 */ a2 2 1
            gd a1 pin 0 adj1 maxAdj1
            gd q1 +- 100000 0 maxAdj1
            gd maxAdj3 */ q1 1 2
            gd a3 pin 0 adj3 maxAdj3
            gd x1 */ ss a3 100000
            gd dx2 */ ss a2 100000
            gd x2 +- hc 0 dx2
            gd x5 +- hc dx2 0
            gd dx3 */ ss a1 200000
            gd x3 +- hc 0 dx3
            gd x4 +- hc dx3 0
            gd x6 +- r 0 x1
            gd dy2 */ ss a2 50000
            gd y2 +- b 0 dy2
            gd y4 +- b 0 dx2
            gd y3 +- y4 0 dx3
            gd y5 +- y4 dx3 0
            gd il */ dx3 x1 dx2
            gd ir +- r 0 il
            ahXY gdRefX=adj1 minX=0 maxX=maxAdj1 x=x3 y=x1
            ahXY gdRefX=adj2 minX=0 maxX=50000 x=x2 y=t
            ahXY gdRefY=adj3 minY=0 maxY=maxAdj3 x=r y=x1
            cxn 3cd4 hc t
            cxn cd2 l y4
            cxn cd4 hc y5
            cxn 0 r y4
            rect il y3 ir y5
            path
            M l y4
            L x1 y2
            L x1 y3
            L x3 y3
            L x3 x1
            L x2 x1
            L hc t
            L x5 x1
            L x4 x1
            L x4 y3
            L x6 y3
            L x6 y2
            L r y4
            L x6 b
            L x6 y5
            L x1 y5
            L x1 b
            Z
            """,
        "leftUpArrow": """
            av adj1 val 25000
            av adj2 val 25000
            av adj3 val 25000
            gd a2 pin 0 adj2 50000
            gd maxAdj1 */ a2 2 1
            gd a1 pin 0 adj1 maxAdj1
            gd maxAdj3 +- 100000 0 maxAdj1
            gd a3 pin 0 adj3 maxAdj3
            gd x1 */ ss a3 100000
            gd dx2 */ ss a2 50000
            gd x2 +- r 0 dx2
            gd y2 +- b 0 dx2
            gd dx4 */ ss a2 100000
            gd x4 +- r 0 dx4
            gd y4 +- b 0 dx4
            gd dx3 */ ss a1 200000
            gd x3 +- x4 0 dx3
            gd x5 +- x4 dx3 0
            gd y3 +- y4 0 dx3
            gd y5 +- y4 dx3 0
            gd il */ dx3 x1 dx4
            gd cx1 +/ x1 x5 2
            gd cy1 +/ x1 y5 2
            ahXY gdRefY=adj1 minY=0 maxY=maxAdj1 x=x3 y=y3
            ahXY gdRefX=adj2 minX=0 maxX=50000 x=x2 y=t
            ahXY gdRefY=adj3 minY=0 maxY=maxAdj3 x=x3 y=x1
            cxn 3cd4 x4 t
            cxn cd2 x2 x1
            cxn 3cd4 x1 y2
            cxn cd2 l y4
            cxn cd4 x1 b
            cxn cd4 cx1 y5
            cxn 0 x5 cy1
            cxn 0 r x1
            rect il y3 x4 y5
            path
            M l y4
            L x1 y2
            L x1 y3
            L x3 y3
            L x3 x1
            L x2 x1
            L x4 t
            L r x1
            L x5 x1
            L x5 y5
            L x1 y5
            L x1 b
            Z
            """,
        "notchedRightArrow": """
            av adj1 val 50000
            av adj2 val 50000
            gd maxAdj2 */ 100000 w ss
            gd a1 pin 0 adj1 100000
            gd a2 pin 0 adj2 maxAdj2
            gd dx2 */ ss a2 100000
            gd x2 +- r 0 dx2
            gd dy1 */ h a1 200000
            gd y1 +- vc 0 dy1
            gd y2 +- vc dy1 0
            gd x1 */ dy1 dx2 hd2
            gd x3 +- r 0 x1
            ahXY gdRefY=adj1 minY=0 maxY=100000 x=r y=y1
            ahXY gdRefX=adj2 minX=0 maxX=maxAdj2 x=x2 y=t
            cxn 3cd4 x2 t
            cxn cd2 x1 vc
            cxn cd4 x2 b
            cxn 0 r vc
            rect x1 y1 x3 y2
            path
            M l y1
            L x2 y1
            L x2 t
            L r vc
            L x2 b
            L x2 y2
            L l y2
            L x1 vc
            Z
            """,
        "quadArrow": """
            av adj1 val 22500
            av adj2 val 22500
            av adj3 val 22500
            gd a2 pin 0 adj2 50000
            gd maxAdj1 */ a2 2 1
            gd a1 pin 0 adj1 maxAdj1
            gd q1 +- 100000 0 maxAdj1
            gd maxAdj3 */ q1 1 2
            gd a3 pin 0 adj3 maxAdj3
            gd x1 */ ss a3 100000
            gd dx2 */ ss a2 100000
            gd x2 +- hc 0 dx2
            gd x5 +- hc dx2 0
            gd dx3 */ ss a1 200000
            gd x3 +- hc 0 dx3
            gd x4 +- hc dx3 0
            gd x6 +- r 0 x1
            gd y2 +- vc 0 dx2
            gd y5 +- vc dx2 0
            gd y3 +- vc 0 dx3
            gd y4 +- vc dx3 0
            gd y6 +- b 0 x1
            gd il */ dx3 x1 dx2
            gd ir +- r 0 il
            ahXY gdRefX=adj1 minX=0 maxX=maxAdj1 x=x3 y=x1
            ahXY gdRefX=adj2 minX=0 maxX=50000 x=x2 y=t
            ahXY gdRefY=adj3 minY=0 maxY=maxAdj3 x=r y=x1
            cxn 3cd4 hc t
            cxn cd2 l vc
            cxn cd4 hc b
            cxn 0 r vc
            rect il y3 ir y4
            path
            M l vc
            L x1 y2
            L x1 y3
            L x3 y3
            L x3 x1
            L x2 x1
            L hc t
            L x5 x1
            L x4 x1
            L x4 y3
            L x6 y3
            L x6 y2
            L r vc
            L x6 y5
            L x6 y4
            L x4 y4
            L x4 y6
            L x5 y6
            L hc b
            L x2 y6
            L x3 y6
            L x3 y4
            L x1 y4
            L x1 y5
            Z
            """,
        "rightArrow": """
            av adj1 val 50000
            av adj2 val 50000
            gd maxAdj2 */ 100000 w ss
            gd a1 pin 0 adj1 100000
            gd a2 pin 0 adj2 maxAdj2
            gd dx1 */ ss a2 100000
            gd x1 +- r 0 dx1
            gd dy1 */ h a1 200000
            gd y1 +- vc 0 dy1
            gd y2 +- vc dy1 0
            gd dx2 */ y1 dx1 hd2
            gd x2 +- x1 dx2 0
            ahXY gdRefY=adj1 minY=0 maxY=100000 x=l y=y1
            ahXY gdRefX=adj2 minX=0 maxX=maxAdj2 x=x1 y=t
            cxn 3cd4 x1 t
            cxn cd2 l vc
            cxn cd4 x1 b
            cxn 0 r vc
            rect l y1 x2 y2
            path
            M l y1
            L x1 y1
            L x1 t
            L r vc
            L x1 b
            L x1 y2
            L l y2
            Z
            """,
        "stripedRightArrow": """
            av adj1 val 50000
            av adj2 val 50000
            gd maxAdj2 */ 84375 w ss
            gd a1 pin 0 adj1 100000
            gd a2 pin 0 adj2 maxAdj2
            gd x4 */ ss 5 32
            gd dx5 */ ss a2 100000
            gd x5 +- r 0 dx5
            gd dy1 */ h a1 200000
            gd y1 +- vc 0 dy1
            gd y2 +- vc dy1 0
            gd dx6 */ dy1 dx5 hd2
            gd x6 +- r 0 dx6
            ahXY gdRefY=adj1 minY=0 maxY=100000 x=l y=y1
            ahXY gdRefX=adj2 minX=0 maxX=maxAdj2 x=x5 y=t
            cxn 3cd4 x5 t
            cxn cd2 l vc
            cxn cd4 x5 b
            cxn 0 r vc
            rect x4 y1 x6 y2
            path
            M l y1
            L ssd32 y1
            L ssd32 y2
            L l y2
            Z
            M ssd16 y1
            L ssd8 y1
            L ssd8 y2
            L ssd16 y2
            Z
            M x4 y1
            L x5 y1
            L x5 t
            L r vc
            L x5 b
            L x5 y2
            L x4 y2
            Z
            """,
        "swooshArrow": """
            av adj1 val 25000
            av adj2 val 16667
            gd a1 pin 1 adj1 75000
            gd maxAdj2 */ 70000 w ss
            gd a2 pin 0 adj2 maxAdj2
            gd ad1 */ h a1 100000
            gd ad2 */ ss a2 100000
            gd xB +- r 0 ad2
            gd yB +- t ssd8 0
            gd alfa */ cd4 1 14
            gd dx0 tan ssd8 alfa
            gd xC +- xB 0 dx0
            gd dx1 tan ad1 alfa
            gd yF +- yB ad1 0
            gd xF +- xB dx1 0
            gd xE +- xF dx0 0
            gd yE +- yF ssd8 0
            gd dy2 +- yE 0 t
            gd dy22 */ dy2 1 2
            gd dy3 */ h 1 20
            gd yD +- t dy22 dy3
            gd dy4 */ hd6 1 1
            gd yP1 +- hd6 dy4 0
            gd xP1 val wd6
            gd dy5 */ hd6 1 2
            gd yP2 +- yF dy5 0
            gd xP2 val wd4
            ahXY gdRefY=adj1 minY=1 maxY=75000 x=xF y=yF
            ahXY gdRefX=adj2 minX=0 maxX=maxAdj2 x=xB y=yB
            cxn cd4 l b
            cxn 3cd4 xC t
            cxn 0 r yD
            cxn cd4 xE yE
            rect l t r b
            path
            M l b
            Q xP1 yP1 xB yB
            L xC t
            L r yD
            L xE yE
            L xF yF
            Q xP2 yP2 l b
            Z
            """,
        "upArrow": """
            av adj1 val 50000
            av adj2 val 50000
            gd maxAdj2 */ 100000 h ss
            gd a1 pin 0 adj1 100000
            gd a2 pin 0 adj2 maxAdj2
            gd dy2 */ ss a2 100000
            gd y2 +- t dy2 0
            gd dx1 */ w a1 200000
            gd x1 +- hc 0 dx1
            gd x2 +- hc dx1 0
            gd dy1 */ x1 dy2 wd2
            gd y1 +- y2 0 dy1
            ahXY gdRefX=adj1 minX=0 maxX=100000 x=x1 y=b
            ahXY gdRefY=adj2 minY=0 maxY=maxAdj2 x=l y=y2
            cxn 3cd4 hc t
            cxn cd2 l y2
            cxn cd4 hc b
            cxn 0 r y2
            rect x1 y1 x2 b
            path
            M l y2
            L hc t
            L r y2
            L x2 y2
            L x2 b
            L x1 b
            L x1 y2
            Z
            """,
        "upDownArrow": """
            av adj1 val 50000
            av adj2 val 50000
            gd maxAdj2 */ 50000 h ss
            gd a1 pin 0 adj1 100000
            gd a2 pin 0 adj2 maxAdj2
            gd y2 */ ss a2 100000
            gd y3 +- b 0 y2
            gd dx1 */ w a1 200000
            gd x1 +- hc 0 dx1
            gd x2 +- hc dx1 0
            gd dy1 */ x1 y2 wd2
            gd y1 +- y2 0 dy1
            gd y4 +- y3 dy1 0
            ahXY gdRefX=adj1 minX=0 maxX=100000 x=x1 y=y3
            ahXY gdRefY=adj2 minY=0 maxY=maxAdj2 x=l y=y2
            cxn 3cd4 hc t
            cxn cd2 l y2
            cxn cd2 x1 vc
            cxn cd2 l y3
            cxn cd4 hc b
            cxn 0 r y3
            cxn 0 x2 vc
            cxn 0 r y2
            rect x1 y1 x2 y4
            path
            M l y2
            L hc t
            L r y2
            L x2 y2
            L x2 y3
            L r y3
            L hc b
            L l y3
            L x1 y3
            L x1 y2
            Z
            """,
        "uturnArrow": """
            av adj1 val 25000
            av adj2 val 25000
            av adj3 val 25000
            av adj4 val 43750
            av adj5 val 75000
            gd a2 pin 0 adj2 25000
            gd maxAdj1 */ a2 2 1
            gd a1 pin 0 adj1 maxAdj1
            gd q2 */ a1 ss h
            gd q3 +- 100000 0 q2
            gd maxAdj3 */ q3 h ss
            gd a3 pin 0 adj3 maxAdj3
            gd q1 +- a3 a1 0
            gd minAdj5 */ q1 ss h
            gd a5 pin minAdj5 adj5 100000
            gd th */ ss a1 100000
            gd aw2 */ ss a2 100000
            gd th2 */ th 1 2
            gd dh2 +- aw2 0 th2
            gd y5 */ h a5 100000
            gd ah */ ss a3 100000
            gd y4 +- y5 0 ah
            gd x9 +- r 0 dh2
            gd bw */ x9 1 2
            gd bs min bw y4
            gd maxAdj4 */ bs 100000 ss
            gd a4 pin 0 adj4 maxAdj4
            gd bd */ ss a4 100000
            gd bd3 +- bd 0 th
            gd bd2 max bd3 0
            gd x3 +- th bd2 0
            gd x8 +- r 0 aw2
            gd x6 +- x8 0 aw2
            gd x7 +- x6 dh2 0
            gd x4 +- x9 0 bd
            gd x5 +- x7 0 bd2
            gd cx +/ th x7 2
            ahXY gdRefX=adj1 minX=0 maxX=maxAdj1 x=th y=b
            ahXY gdRefX=adj2 minX=0 maxX=25000 x=x6 y=b
            ahXY gdRefY=adj3 minY=0 maxY=maxAdj3 x=x6 y=y4
            ahXY gdRefX=adj4 minX=0 maxX=maxAdj4 x=bd y=t
            ahXY gdRefY=adj5 minY=minAdj5 maxY=100000 x=r y=y5
            cxn cd4 x6 y4
            cxn cd4 x8 y5
            cxn 0 r y4
            cxn 3cd4 cx t
            cxn cd4 th2 b
            rect l t r b
            path
            M l b
            L l bd
            A bd bd cd2 cd4
            L x4 t
            A bd bd 3cd4 cd4
            L x9 y4
            L r y4
            L x8 y5
            L x6 y4
            L x7 y4
            L x7 x3
            A bd2 bd2 0 -5400000
            L x3 th
            A bd2 bd2 3cd4 -5400000
            L th b
            Z
            """,
    ]
}
