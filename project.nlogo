;========================
; Libraries & Extensions
;========================

;========================
; GLOBALS AND BREEDS
;========================

breed [ farmers farmer ]
farmers-own [ land-size wealth crop-stage crop-quality available-water required-water friendliness social-credit theft-history last-stolen my-turn? predicted-water crop-type crop-water-profile]
undirected-link-breed [ friendships friendship ]
friendships-own [ water-a-to-b-balance strength ]
directed-link-breed [ thefts theft ]
thefts-own [ amount-stolen ]
globals [total-land farmer-order rice-req cotton-req wheat-req mustard-req week season total-flow total-thefts detected-thefts current-event last-flood? rainfall-factor growth-efficiency total-trades trade-volume theft-volume ]

;========================
; SETUP FUNCTIONS
;========================

to setup
  clear-all
  reset-ticks
  ;sr:setup ; SimpleR setup
  setup-patches
  setup-farmers
  setup-friendships
  set week 1
  set total-trades 0
  set trade-volume 0
  set total-thefts 0
  set theft-volume 0
  set detected-thefts 0
  set season "rabi"
  set total-flow base-flow
  ; baseline values taken from https://www.mdpi.com/2077312 & https://link.springer.com/article/10.1007/s44279-025-00189-5
  set rice-req   [0.7 0.9 1.0 1.2 1.3 1.3 1.2 1.1 1.0 0.9 0.8 0.7 0.6 0.5]
  set cotton-req [0.6 0.7 0.8 1.0 1.1 1.1 1.0 0.9 0.8 0.7]
  set wheat-req  [0.4 0.5 0.6 0.7 0.7 0.6 0.5 0.4]
  set mustard-req [0.4 0.5 0.6 0.7 0.7 0.6 0.5 0.4]
  set current-event "none"
  set last-flood? false
  set rainfall-factor 1.0
  set growth-efficiency 1.0
  assign-crops ; assign initial crops based on season
  update-land ; mark farmland based on crop stage
end

to setup-patches
  ask patches with [pxcor = min-pxcor] [ set pcolor blue ] ; water channel on the left
end

to setup-farmers
  let temp-count 0
  set farmer-order []
  create-farmers num-farmers [
    set shape "person farmer" ; agent is a farmer
    set land-size min(list 31 max(list 3 int exp (random-normal 1.5 0.8))) ; give random amount of land
    set social-credit ln(land-size + 1) + random-float 0.5 ; my social standing depends on how much land I have
    ;set land-size max(list 3 int (random-normal 10 5)) ; give random amount of land
    ;set crop-stage random 5 ; crop stage is between 0 - 4 initially
    ;set crop-quality 0.8 + (random-float 0.4) ; crop quality is between 0.8 - 1.2 initially
    set total-land total-land + land-size ; update total for water division
    setxy (1 + land-size / 2) (length farmer-order) ; place agent in the middle of their land in their corresponding row
    set farmer-order lput self farmer-order ; create ordering of farmers from bottom to top
    set friendliness random-float 1; initial friendliness for social sharing
    set theft-history []
  ]

end

to setup-friendships
  ask farmers [
  ; 1. Spatial neighbor (ycor + 1)
  let neighbor-farmer one-of farmers with [ycor = [ycor] of myself + 1 and not link-neighbor? myself]
  if neighbor-farmer != nobody [
    create-friendship-with neighbor-farmer [
      set water-a-to-b-balance 0
      set strength [friendliness] of end1 * [friendliness] of end2
    ]
  ]

  ;; 2. Similar social credit (2 closest)
  let oth other turtles with [not member? self [who] of friendship-neighbors]
    let sorted-list sort-by [ [a b] -> abs([social-credit] of a - [social-credit] of self) < abs([social-credit] of b - [social-credit] of self)] oth
  let similar-sc sublist sorted-list 0 2
  foreach similar-sc [ f ->
    create-friendship-with f [
      set water-a-to-b-balance 0
      set strength [friendliness] of end1 * [friendliness] of end2
    ]
  ]

  ;; 3. Random farmer (1)
  let available-randoms other farmers with [not link-neighbor? myself]
  if any? available-randoms [
    create-friendship-with one-of available-randoms [
      set water-a-to-b-balance 0
      set strength [friendliness] of end1 * [friendliness] of end2
    ]
  ]
  ]

  ask friendships [
    set color scale-color red (abs water-a-to-b-balance) 1 0
  ]
end

to assign-crops
  ask farmers [
    if season = "rabi" [
      ifelse random-float 1 < 0.5 [
        set crop-type "wheat"
        set crop-water-profile wheat-req
      ][
        set crop-type "mustard"
        set crop-water-profile mustard-req
      ]
    ]
    if season = "kharif" [
      ifelse random-float 1 < 0.5 [
        set crop-type "rice"
        set crop-water-profile rice-req
      ][
        set crop-type "cotton"
        set crop-water-profile cotton-req
      ]
    ]
    set crop-stage 0 ; initialize crop stage
    set crop-quality 1 ; initialize crop quality
  ]
end

to-report my-land
  report patches with [ pycor = [ycor] of myself and pxcor > 0 and pxcor <= [land-size] of myself ] ; update color of my farmland depending on crop stage
end

to update-land
  ask farmers [ ask my-land [ set pcolor scale-color ([color] of myself) ([crop-stage] of myself) -10 (10 + length [crop-water-profile] of myself)]] ; mark my land based on how close to harvest
end

;========================
; GO / MAIN LOOP
;========================

to go
  if ticks >= 520 [ stop ] ; simulation end after 520 ticks
  set week week + 1
  if week > 26 [ set week 1 ] ; reset week every 26
  update-season ; switch crops if new season
  check-environment ; decide flood/drought/heavy-rain
  update-water-flow ; set water flow based on season and rainfall
  apply-environment-effects ; apply crop damage from events
  update-land ; update farmland color/stage
  allocate-water ; distribute water to farmers based on availability
  share-water ; farmers request/share water with their connections
  attempt-theft ; farmers attempt to steal water
  update-theft-links ; visualise theft amounts
  ask farmers [ grow-crops ] ; update crop growth and quality
  tick
end

;========================
; ENVIRONMENT
;========================

to check-environment
  set current-event "none"
  set rainfall-factor 1.0
  set growth-efficiency 1.0

  let r random-float 1
  if r < 0.03 [
    set current-event "flood"
    set rainfall-factor (1.5 + random-float 0.8) ; 1.5–2.3× flow
    set growth-efficiency 0.8 ; waterlogging => less effective growth now
  ]
  if r >= 0.03 and r < 0.10 [
    set current-event "heavy-rain"
    set rainfall-factor (1.2 + random-float 0.5) ; 1.2–1.7× flow
    set growth-efficiency 0.9 ; some waterlogging reduces effective growth
  ]
  if r >= 0.10 and r < 0.15 [
    set current-event "drought"
    set rainfall-factor (0.4 + (random-float 0.4)) ; 0.4–0.8× flow
    set growth-efficiency 0.9 ; heat/drought stress may slightly lower efficiency
    ask farmers [
      set available-water available-water * rainfall-factor ; reduce water in drought
    ]
  ]
end

to apply-environment-effects
  if current-event = "flood" [
    ask farmers [
      set crop-quality crop-quality * (0.5 + random-float 0.3)  ; 50–80% survival
    ]
    set last-flood? true
  ]
  if current-event = "heavy-rain" [
    ask farmers [
      set crop-quality crop-quality * (0.85 + random-float 0.05)  ; small reduction
    ]
  ]
  if current-event = "drought" [
    ask farmers [
      set crop-quality crop-quality * (0.6 + random-float 0.2)  ; 60–80% of previous
    ]
  ]
end

;========================
; WATER MANAGEMENT
;========================

to update-water-flow
  let season-factor 1.0
  if season = "kharif" [ set season-factor 1.4 ]
  if season = "rabi"   [ set season-factor 0.6 ]
  set total-flow base-flow * season-factor ; base flow * season factor
  set total-flow total-flow * rainfall-factor ; apply rainfall/drought factor
  set total-flow total-flow * (0.8 + random-float 0.4) ; random fluctuation
  if total-flow < 0 [ set total-flow 0 ]
end

to allocate-water
  let water-per-acre total-flow / total-land; total water available to distribute
  ask farmers [
    set required-water land-size * item crop-stage crop-water-profile ; water needed for this farmer's land & crop stage
    let loss-factor 1 - (0.01 * ycor); more loss further downstream -> higher ycor. for 32 pos, 32% water loss
    set available-water land-size * water-per-acre * (loss-factor + random-float 0.05) ; get water as per land (and loss w/ some randomness)
    set predicted-water available-water ; I expect to receive as much as allocated
  ]
end

to share-water
  ask farmers [
    let deficit required-water - available-water
    if deficit <= 0 [ stop ]   ;; skip if no need

    let available_ratio available-water / required-water
    let a 8
    let p_ask 1 / (1 + exp (- a * (1 - available_ratio))) ; low water -> high chance to ask

    let cnt 0
    let limit 5
    while [ random-float 1 < p_ask and cnt < limit ] [
      set cnt cnt + 1

      let friend one-of friendship-neighbors
      if friend != nobody [
        ask friend [
          ;; Determine how much I can give
          let my-surplus available-water - required-water
          if my-surplus < 0 [ set my-surplus 0 ]
          let max-give my-surplus * 0.5  ;; never give more than half surplus

          if max-give > 0 [
            ;; get connection
            let friend-link friendship ([who] of self) ([who] of myself)

            ;; acceptance probability depends on:
            ;; - my friendliness
            ;; - strength of the tie
            ;; - balance history
            ;; - social credit of requester
            let f  friendliness
            let sc [social-credit] of myself
            let str [strength] of friend-link
            let bal [water-a-to-b-balance] of friend-link
            ;show friend-link
            if ([who] of self = [end1] of friend-link) [set bal (- bal) ]

            ;; logistic acceptance probability -> each parameter normalised to -1 to 1
            let accept-factor (
              base-share              + ;; don't give water if no real need
              w_f * 2 * (f - 0.5)            +   ;; friendly farmers give more
              w_str * 2 * (str - 0.5)        +   ;; strong friendship
              w_bal * bal        +   ;; positive trade history
              w_sc * 0.1 * sc         +   ;; high-social-credit requester
              w_def * 1 * (deficit / [required-water] of myself) ;; urgent need
            )
            let p_accept 1 / (1 + exp (-(accept-factor)))
            ;show deficit
            ;show p_accept

            ifelse random-float 1 < p_accept [
              ;show "accept"
              ;; actual transfer amount
              let amount min (list max-give deficit)

              ;; donor gives
              set available-water available-water - amount

              ;; requester receives
              ask myself [
                set available-water available-water + amount
              ]

              ;; update friendship
              ask friend-link [
                ifelse ([who] of myself = [end1] of friend-link) ; update balance in correct direction
                [ set water-a-to-b-balance water-a-to-b-balance + amount ]
                [ set water-a-to-b-balance water-a-to-b-balance - amount ]
                set strength min(list 1 (strength + 0.1))
                set color scale-color red (abs water-a-to-b-balance) 1 0
                set total-trades (total-trades + 1)
                set trade-volume trade-volume + amount
              ]
              set social-credit (social-credit + 0.1 * sc)
            ]
            [ ask friend-link [ set strength (strength * 0.95) ] ]
          ]
        ]
      ]
    set deficit required-water - available-water
    if deficit <= 0 [ stop ]   ;; skip if no need

    set available_ratio available-water / required-water
    set p_ask 1 / (1 + exp (- a * (1 - available_ratio))) ; low water -> high chance to ask
    ]
  ]
end



;========================
; THEFT
;========================

;========================
; THEFT (new version)
;========================

to attempt-theft
  let thefts-this-tick []

  ;; each farmer can attempt up to 3 thefts in one tick
  foreach farmer-order [
    thief ->
    ask thief [

      let remaining-deficit required-water - available-water
      if remaining-deficit <= 0 [ stop ]

      ;; pick possible victims (e.g. downstream)
      let candidates other farmers with [ pycor > [pycor] of thief ]
      if not any? candidates [ stop ]

      ;; sort by: high water, low social credit, weak ties (easier to steal from)
      let sorted-targets sort-by [ [a b] -> (heuristic-value self a) > (heuristic-value self b) ] candidates


      ;; thief can try up to 3 different victims
      let tries 0

      while [tries < 3 and remaining-deficit > 0 and (length sorted-targets) > 0] [

        let victim first sorted-targets
        set sorted-targets but-first sorted-targets
        set tries tries + 1

        ;; --- Compute theft probability ------------------------

        let deficit-ratio remaining-deficit / required-water ; would steal if i have more deficit
        let victim-water [available-water] of victim ; more likely to steal if other person has a lot of water
        let friendly-thief friendliness ; wouldn't want to steal if i am friendly
        let sc-thief social-credit ; wouldn't wat to steal if i have people's respect -> won't want to harm image
        let sc-victim [social-credit] of victim ; would be more likely to steal from people with less social credit
        let victim-wealth [ wealth ] of victim ; less likely to steal from rich as they can take legal action - ignore for now
        let str 0
        if (friendship-neighbor? victim) [set str [strength] of friendship (who) ([who] of victim)]

        ;; retaliation: if victim was recently stolen
        ; let retaliation (ifelse-value ([last-stolen] of victim > 0) [0.5] [1])

        ;; FEATURES → logistic acceptance P(theft)
        let x (
          base-theft +
          theft_w_def   * deficit-ratio +                      ; my deficit
          theft_w_vwater * (victim-water / 10) +
          theft_w_f     * (-2 * (friendly-thief - 0.5)) +       ; my friendliness
          theft_w_sc    * (- sc-thief / 10) +
          theft_w_vsc    * (- sc-victim / 10) +          ; low social-credit victim easier
          theft_w_str   * (- str)                           ; less likely to steal from friends
          ; w_ret   * retaliation
        )

        let p-steal 1 / (1 + exp (- x))

        ;; --- Attempt theft -------------------------------------
        if random-float 1 < p-steal [

          ;; amount: min of deficit and upto 20% of victim water
          let amount min (list remaining-deficit ((random-float 0.2) * victim-water))

          if amount > 0 [

            ;; thief gets water
            set available-water available-water + amount
            set social-credit social-credit - 0.05   ;; slight penalty
            set friendliness friendliness * 0.97     ;; becomes slightly less kind

            ;; victim loses water
            ask victim [
              set available-water available-water - amount
            ]

            ;; update friendship tie
            if (friendship-neighbor? victim) [
              ask (friendship (who) ([who] of victim)) [ set strength 0.8 * strength ]
            ]

            ;; record theft
            set total-thefts total-thefts + 1
            set theft-volume theft-volume + amount
            if (not theft-neighbor? victim) [ create-theft-to victim [ set amount-stolen 0 ] ]
            ask theft who ([who] of victim) [ set amount-stolen (amount-stolen + amount) ]
            set thefts-this-tick lput (list thief victim amount) thefts-this-tick

            ;; update remaining deficit
            set remaining-deficit required-water - available-water
          ]
        ]
      ]
    ]
  ]
end

to detect2
  ;; --- Detection phase ---------------------------------------
  let thefts-this-tick [] ; remove line
  foreach thefts-this-tick [
    t ->
      let thief first t
      let victim item 1 t
      let stolen item 2 t
      let predicted [predicted-water] of victim
      let actual [available-water] of victim

      ;; strong deviation indicates likely theft
      let deviation predicted - actual
      let threshold 0.25 * predicted

      if deviation > threshold and random-float 1 < 0.7 [
        ask victim [
          set last-stolen deviation
          set friendliness friendliness * 0.6
          set social-credit 0
        ]
        set detected-thefts detected-thefts + 1
      ]
  ]

  ;; post-detection penalty to victims
  ask farmers [
    if last-stolen > 0 [
      set friendliness friendliness * 0.8
      set social-credit social-credit * 0.8
    ]
    set last-stolen 0
  ]
end

to update-theft-links
  ask thefts [
    if (amount-stolen > 0) [ set color red]
  ]
end
;;;;;;;;dadadad

to attempt-theft2
  let thefts-tick []  ; collect all thefts this tick
  foreach farmer-order [
    thief ->
      ask thief [
        let deficit required-water - available-water  ; how much water thief still needs
        if deficit > 0 [
          let possible-targets other farmers with [ pycor > [pycor] of thief ]  ; only downstream farmers
          if any? possible-targets [
            let sorted-targets sort-by [[a b] -> (([available-water] of a + [social-credit] of a) > ([available-water] of b + [social-credit] of b))] possible-targets  ; prioritize richer/creditworthy targets
            let victim first sorted-targets  ; choose first as victim
            let base-prob 0.2  ; base probability of attempting theft
            let water-factor min list 1 (deficit / required-water)  ; more deficit -> higher probability
            let social-factor 1 - ([social-credit] of victim / 10)  ; victim’s social credit reduces theft chance
            let friend-factor 1 - [friendliness] of victim  ; friendly victims are harder to steal from
            let upstream-factor 1 - (position thief farmer-order * 0.05)  ; upstream farmers less likely to steal
            let retaliation-factor ifelse-value ([last-stolen] of victim > 0) [0.5] [1]  ; reduce chance if victim was recently stolen
            let theft-prob base-prob * water-factor * social-factor * friend-factor * upstream-factor * retaliation-factor  ; final probability
            if random-float 1 < theft-prob [
              let stolen min list deficit (0.5 * [available-water] of victim)  ; thief can take up to 50% of victim’s water
              set available-water available-water + stolen  ; thief gains stolen water
              set social-credit social-credit - 0.1  ; penalty for thief
              ask victim [
                set available-water available-water - stolen  ; victim loses water
                set friendliness friendliness - 0.2  ; victim trust decreases
              ]
              set thefts-tick lput (list thief victim stolen) thefts-tick  ; record theft
            ]
          ]
        ]
      ]
  ]
  set total-thefts total-thefts + length thefts-tick  ; update global theft count
  foreach thefts-tick [
    t ->
      let thief first t
      let victim item 1 t
      let stolen item 2 t
      let deviation ([predicted-water] of victim - [available-water] of victim)  ; how much water missing
      let threshold 0.25 * [predicted-water] of victim  ; detection threshold
      if deviation > threshold and random-float 1 < 0.7 [
        ask victim [
          set last-stolen deviation  ; mark theft
          set friendliness friendliness * 0.6  ; reduce trust strongly
          set social-credit 0  ; reset social credit
        ]
        set detected-thefts detected-thefts + 1  ; global detection count
      ]
  ]
  ask farmers [
    if last-stolen > 0 [
      set friendliness friendliness * 0.8  ; reduce trust
      set social-credit social-credit * 0.8  ; reduce social credit
    ]
  ]
  ask farmers [ set last-stolen 0 ]  ; reset for next tick
end

to check-theft-detection2 [ victim ]
  let deviation ([predicted-water] of victim - [available-water] of victim)  ; how much water victim lost
  let threshold 0.25 * [predicted-water] of victim  ; threshold for detecting theft
  if deviation > threshold and random-float 1 < 0.5 [  ; check if theft is noticed (50% chance)
    ask victim [
      set last-stolen deviation  ; mark how much was stolen
      set friendliness friendliness * 0.5  ; reduce trust due to theft
      set social-credit 0  ; reset social credit after theft
    ]
    set detected-thefts detected-thefts + 1  ; increment global detected theft count
  ]
end

;========================
; GROWTH & CROP
;========================

to grow-crops
  let multiplier (available-water / required-water) * growth-efficiency  ; calculate growth multiplier based on water & global growth factor
  set multiplier max (list 0.8 (min list multiplier 1.2))  ; clamp multiplier to prevent extreme growth/decay
  set crop-quality crop-quality * multiplier  ; update crop quality based on water received and growth efficiency
  set crop-stage crop-stage + 1  ; advance crop stage
  if crop-stage >= length crop-water-profile [  ; check if crop reached final stage
    set wealth wealth + (crop-quality * land-size)  ; harvest: wealth gain proportional to quality & land
    set crop-stage 0  ; reset crop stage for next planting
    set crop-quality 1  ; reset crop quality to baseline
  ]
end

to update-season
  if week = 1 [  ; every 26 weeks, switch season
    ifelse season = "rabi" [set season "kharif"][set season "rabi"]  ; toggle season
    ask farmers [
      if season = "rabi" [
        ifelse random-float 1 < 0.5 [
          set crop-type "wheat"  ; assign wheat randomly
          set crop-water-profile wheat-req  ; set corresponding water profile
        ][
          set crop-type "mustard"  ; assign mustard otherwise
          set crop-water-profile mustard-req
        ]
      ]
      if season = "kharif" [
        ifelse random-float 1 < 0.5 [
          set crop-type "rice"  ; assign rice randomly
          set crop-water-profile rice-req
        ][
          set crop-type "cotton"  ; assign cotton otherwise
          set crop-water-profile cotton-req
        ]
      ]
      set crop-stage 0  ; reset crop stage for new season
      set crop-quality 1  ; reset crop quality
      if last-flood? [set crop-quality crop-quality * 1.1]  ; apply flood fertility bonus if last season had flood
    ]
    set last-flood? false  ; clear flood flag after applying bonus
  ]
end


;========================
; Helpers
;========================

to-report heuristic-value [me target]
  let w [available-water] of target
  let sc [social-credit] of target
  let str 0

  if [friendship-neighbor? target] of me [
    set str [strength] of (friendship ([who] of me) ([who] of target))
  ]

  report w - 0.5 * (sc / 10) - 0.3 * str
end
@#$#@#$#@
GRAPHICS-WINDOW
438
14
875
452
-1
-1
13.0
1
10
1
1
1
0
0
0
1
0
32
0
32
0
0
1
ticks
30.0

BUTTON
32
27
99
60
NIL
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
179
27
242
60
NIL
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
49
77
221
110
num-farmers
num-farmers
0
33
33.0
1
1
NIL
HORIZONTAL

MONITOR
271
20
343
65
NIL
total-land
17
1
11

SLIDER
49
122
221
155
base-flow
base-flow
0
500
50.0
5
1
NIL
HORIZONTAL

PLOT
916
19
1138
191
Water Required
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 1 -13840069 true "" "histogram [required-water] of farmers"

PLOT
917
223
1148
390
Crop Quality
NIL
NIL
0.0
5.0
0.0
10.0
true
false
"" ""
PENS
"default" 0.2 1 -2674135 true "" "histogram [crop-quality] of farmers"

BUTTON
107
27
170
60
step
go
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

PLOT
913
430
1153
609
Water Incoming
Ticks
Water Inflow
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot total-flow"

PLOT
1184
20
1384
170
Friendliness of Farmers
Ticks
Value
0.0
10.0
0.0
10.0
true
false
"set-plot-y-range 0 1\n\n" ""
PENS
"Friendliness" 1.0 0 -8330359 true "" "if any? farmers [plot mean [friendliness] of farmers]"

PLOT
1195
228
1395
378
Social Credits of Farmers
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"Social credits" 1.0 0 -16777216 true "" "if any? farmers [ plotxy ticks mean [social-credit] of farmers ]"

PLOT
1200
442
1400
592
Thefts
Ticks
Amount
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"Total Thefts" 1.0 0 -13791810 true "" "plot total-thefts\n\n"
"Detected Thefts" 1.0 0 -2674135 true "" "plot detected-thefts"

MONITOR
36
168
234
213
friendship strength
mean [strength] of friendships
17
1
11

PLOT
1448
139
1734
500
Friendship Balance
NIL
NIL
-1.0
1.0
0.0
400.0
true
false
"" ""
PENS
"default" 0.1 1 -16777216 true "" "histogram [water-a-to-b-balance] of friendships"

SLIDER
50
543
222
576
w_f
w_f
0
3
1.5
0.1
1
NIL
HORIZONTAL

SLIDER
46
674
218
707
w_sc
w_sc
0
3
2.0
0.1
1
NIL
HORIZONTAL

SLIDER
48
584
220
617
w_str
w_str
0
3
2.0
0.1
1
NIL
HORIZONTAL

SLIDER
47
628
219
661
w_bal
w_bal
0
3
1.0
0.1
1
NIL
HORIZONTAL

SLIDER
46
718
218
751
w_def
w_def
0
3
1.5
0.1
1
NIL
HORIZONTAL

SLIDER
49
499
221
532
base-share
base-share
-5
5
3.0
0.1
1
NIL
HORIZONTAL

MONITOR
39
234
122
279
NIL
total-trades
17
1
11

MONITOR
33
287
128
332
NIL
trade-volume
17
1
11

SLIDER
296
718
468
751
theft_w_def
theft_w_def
0
3
1.5
0.1
1
NIL
HORIZONTAL

SLIDER
297
531
469
564
theft_w_vwater
theft_w_vwater
0
3
1.0
0.1
1
NIL
HORIZONTAL

SLIDER
298
495
470
528
base-theft
base-theft
-20
20
-7.0
0.1
1
NIL
HORIZONTAL

SLIDER
298
568
470
601
theft_w_f
theft_w_f
0
3
1.0
0.1
1
NIL
HORIZONTAL

SLIDER
297
642
469
675
theft_w_sc
theft_w_sc
0
3
2.0
0.1
1
NIL
HORIZONTAL

SLIDER
296
680
468
713
theft_w_vsc
theft_w_vsc
0
3
2.0
0.1
1
NIL
HORIZONTAL

SLIDER
296
605
468
638
theft_w_str
theft_w_str
0
3
2.0
0.1
1
NIL
HORIZONTAL

MONITOR
223
233
303
278
NIL
total-thefts
17
1
11

MONITOR
218
291
310
336
NIL
theft-volume
17
1
11

@#$#@#$#@
## WHAT IS IT?

(a general understanding of what the model is trying to show or explain)

## HOW IT WORKS

(what rules the agents use to create the overall behavior of the model)

## HOW TO USE IT

total-flow is in 1000 m^3 / acre
land is in acres
(how to use the model, including a description of each of the items in the Interface tab)

## THINGS TO NOTICE

(suggested things for the user to notice while running the model)

## THINGS TO TRY

(suggested things for the user to try to do (move sliders, switches, etc.) with the model)

## EXTENDING THE MODEL

(suggested things to add or change in the Code tab to make the model more complicated, detailed, accurate, etc.)

## NETLOGO FEATURES

(interesting or unusual features of NetLogo that the model uses, particularly in the Code tab; or where workarounds were needed for missing features)

## RELATED MODELS

(models in the NetLogo Models Library and elsewhere which are of related interest)

## CREDITS AND REFERENCES

(a reference to the model's URL on the web if it has one, as well as any other necessary credits, citations, and links)
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

person farmer
false
0
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Polygon -1 true false 60 195 90 210 114 154 120 195 180 195 187 157 210 210 240 195 195 90 165 90 150 105 150 150 135 90 105 90
Circle -7500403 true true 110 5 80
Rectangle -7500403 true true 127 79 172 94
Polygon -13345367 true false 120 90 120 180 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 180 90 172 89 165 135 135 135 127 90
Polygon -6459832 true false 116 4 113 21 71 33 71 40 109 48 117 34 144 27 180 26 188 36 224 23 222 14 178 16 167 0
Line -16777216 false 225 90 270 90
Line -16777216 false 225 15 225 90
Line -16777216 false 270 15 270 90
Line -16777216 false 247 15 247 90
Rectangle -6459832 true false 240 90 255 300

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.4.0
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
