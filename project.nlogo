;========================
; GLOBALS AND BREEDS
;========================

breed [ farmers farmer ]
farmers-own [ land-size wealth crop-stage crop-quality available-water required-water friendliness social-credit theft-history last-stolen my-turn? crop-type crop-water-profile shared-now stolen-now suspicion-threshold
              seed-cost maintenance-cost harvest-price total-cost revenue p-steal-base share-aggressiveness current-strategy living-cost times-robbed num-trades num-shares crops-used strategies-used ] ; added crop economic variables & farmer strategy

undirected-link-breed [ friendships friendship ]
friendships-own [ water-a-to-b-balance strength ]
directed-link-breed [ thefts theft ]
thefts-own [ amount-stolen ]
globals [total-land farmer-order rice-req cotton-req wheat-req mustard-req week season total-flow total-thefts detected-thefts current-event last-flood? rainfall-factor growth-efficiency total-trades trade-volume theft-volume total-theft-checks dropped-friendships]

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
  set total-theft-checks 0
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
  show-wealth
  show-social-credit
end

to setup-patches
  ask patches with [pxcor = min-pxcor] [ set pcolor blue ] ; water channel on the left
end

to setup-farmers
  let temp-count 0
  set farmer-order []
  create-farmers num-farmers [
    set shape "person farmer" ; agent is a farmer
    set land-size min(list 29 max(list 3 int exp (random-normal 1.5 0.8))) ; give random amount of land
    if land-size < 7 [ set living-cost 0.5 * base-living-cost-month ]
    if (land-size >= 7 and land-size < 15) [ set living-cost base-living-cost-month ]
    if land-size >= 15 [ set living-cost 1.5 * base-living-cost-month ]
    set social-credit ln(land-size + 1) + random-float 0.5 ; my social standing depends on how much land I have
    set suspicion-threshold (0.05 + random-float 0.2) ; 0.05 -> 0.25
    ;set land-size max(list 3 int (random-normal 10 5)) ; give random amount of land
    ;set crop-stage random 5 ; crop stage is between 0 - 4 initially
    ;set crop-quality 0.8 + (random-float 0.4) ; crop quality is between 0.8 - 1.2 initially
    set total-land total-land + land-size ; update total for water division
    setxy (1 + land-size / 2) (length farmer-order) ; place agent in the middle of their land in their corresponding row
    set farmer-order lput self farmer-order ; create ordering of farmers from bottom to top
    set friendliness random-float 1; initial friendliness for social sharing
    set theft-history []
    set times-robbed 0
    set num-trades 0
    set crops-used n-values 4 [ 0 ]
    set strategies-used n-values 4 [ 0 ]
    set wealth land-size * 20000
  ]

end

to setup-friendships
  set dropped-friendships 0
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
    let option1 ""
    let option2 ""
    if season = "kharif" [
      set option1 "rice" ; Kharif Crop Option 1
      set option2 "cotton" ; Kharif Crop Option 2
    ]
    if season = "rabi" [
      set option1 "wheat" ; Rabi Crop Option 1
      set option2 "mustard" ; Rabi Crop Option 2
    ]

    ; 1. GET PROFILES: Returns [profit, efficiency, total-cost, total-water-req]
    let profile1 crop-economic-profile option1
    let profile2 crop-economic-profile option2

    let profit1 item 0 profile1
    let efficiency1 item 1 profile1
    let cost1 item 2 profile1
    ; let total-water-req1 item 3 profile1 ; Not needed in this block, but available

    let profit2 item 0 profile2
    let efficiency2 item 1 profile2
    let cost2 item 2 profile2
    ; let total-water-req2 item 3 profile2 ; Not needed in this block, but available

    ; 2. DYNAMIC THRESHOLDS AND VIABILITY (Farmer-Specific Rationality)
    let max-seasonal-cost max (list cost1 cost2) ; Max estimated cost this season
    let viable-options (list)

    ; Check Affordability based on Estimated Total Cost
    if wealth >= cost1 [ set viable-options lput option1 viable-options ]
    if wealth >= cost2 [ set viable-options lput option2 viable-options ]

    let final-choice ""
    let strategic-choice? false

    ; 3. STRATEGIC DECISION (Only proceeds if at least one crop is affordable)
    if not empty? viable-options [

      ; A. MAX PROFIT (RISK/REWARD) STRATEGY:
      ; Farmer is highly secure (wealth is > 2x max-cost) AND water stress is low
      if wealth > (max-seasonal-cost * 2) [
        set strategic-choice? true

        ; Select highest profit among viable options
        if (member? option1 viable-options) and (profit1 > profit2 or not member? option2 viable-options) [ set final-choice option1 ]
        if (member? option2 viable-options) and (profit2 > profit1 or not member? option1 viable-options) [ set final-choice option2 ]

        ; Tie-breaker
        if final-choice = "" [ set final-choice one-of viable-options ]
      ]

      ; B. MAX EFFICIENCY (SURVIVAL) STRATEGY:
      ; Farmer is stressed (wealth is low)
      if (not strategic-choice?) and (wealth < (max-seasonal-cost * 1.5)) [
        set strategic-choice? true

        ; Select highest efficiency among viable options
        if (member? option1 viable-options) and (efficiency1 > efficiency2 or not member? option2 viable-options) [ set final-choice option1 ]
        if (member? option2 viable-options) and (efficiency2 > efficiency1 or not member? option1 viable-options) [ set final-choice option2 ]

        ; Tie-breaker
        if final-choice = "" [ set final-choice one-of viable-options ]
      ]

      ; C. DEFAULT STRATEGY (Medium wealth): Random selection from affordable crops
      if not strategic-choice? [
        set final-choice one-of viable-options
        set strategic-choice? true
      ]
    ]

    ; 4. FINAL FALLBACK: If NO crop is affordable (viability check failed for both)
    if final-choice = "" [
      ; Farmer is forced to take the cheapest option and assume debt or extreme risk
      ifelse (cost1 < cost2) [
        set final-choice option1 ; Cost 1 is cheaper
      ] [
        set final-choice option2 ; Cost 2 is cheaper or costs are equal
      ]
      set strategic-choice? false
    ]

    ; 5. Apply Chosen Crop Attributes and Deduct Costs (This is critical to do only once)
    apply-crop-attributes final-choice

  ]
end


to apply-crop-attributes [chosen-crop]
  set crop-type chosen-crop

  if chosen-crop = "rice" [
    set crop-water-profile rice-req
    set seed-cost rice-seed-cost + random-float (0.2 * rice-seed-cost)
    set maintenance-cost base-maintenance-cost + random-float 2000
    set harvest-price rice-price
    let tmp item 0 crops-used
    set tmp tmp + 1
    set crops-used replace-item 0 crops-used tmp
  ]
  if chosen-crop = "cotton" [
    set crop-water-profile cotton-req
    set seed-cost cotton-seed-cost + random-float (0.2 * cotton-seed-cost)
    set maintenance-cost 2 * base-maintenance-cost + random-float 3000
    set harvest-price cotton-price
    let tmp item 1 crops-used
    set tmp tmp + 1
    set crops-used replace-item 1 crops-used tmp
  ]
  if chosen-crop = "wheat" [
    set crop-water-profile wheat-req
    set seed-cost wheat-seed-cost + random-float (0.3 * wheat-seed-cost)
    set maintenance-cost base-maintenance-cost + random-float 1000
    set harvest-price wheat-price
    let tmp item 2 crops-used
    set tmp tmp + 1
    set crops-used replace-item 2 crops-used tmp
  ]
  if chosen-crop = "mustard" [
    set crop-water-profile mustard-req
    set seed-cost mustard-seed-cost + random-float (0.1 * mustard-seed-cost)
    set maintenance-cost 0.5 * base-maintenance-cost + random-float 500
    set harvest-price mustard-price
    let tmp item 3 crops-used
    set tmp tmp + 1
    set crops-used replace-item 3 crops-used tmp
  ]

  ; Final Cost Calculation and Deduction (Done ONLY ONCE)
  set total-cost seed-cost + maintenance-cost ; total crop cost
  set wealth wealth - total-cost * land-size; deduct cost at start of season

  ; Reset growth variables
  set crop-stage ((random (crop-stage-variance + 1)) - crop-stage-variance)
  set crop-quality 1
  set revenue 0 ; reset revenue
end

to-report crop-economic-profile [crop-name]
  let seed 0
  let price 0
  let water-profile []
  let maintenance 0

  if crop-name = "rice" [
    set seed rice-seed-cost
    set price rice-price
    set water-profile rice-req
    set maintenance base-maintenance-cost
  ]
  if crop-name = "cotton" [
    set seed cotton-seed-cost
    set price cotton-price
    set water-profile cotton-req
    set maintenance 2 * base-maintenance-cost
  ]
  if crop-name = "wheat" [
    set seed wheat-seed-cost
    set price wheat-price
    set water-profile wheat-req
    set maintenance base-maintenance-cost
  ]
  if crop-name = "mustard" [
    set seed mustard-seed-cost
    set price mustard-price
    set water-profile mustard-req
    set maintenance 0.5 * base-maintenance-cost
  ]

  ; Calculate total water required (sum of weekly reqs)
  let total-water-req (sum water-profile)

  ; CALCULATE ESTIMATED WATER COST: Base Cost per Unit * Total units required * Land Size
  ; NOTE: Assuming 'base-water-cost-per-unit' is the global for water price.
  let water-cost (base-water-cost-per-unit * total-water-req * land-size)

  ; UPDATED: Total estimated cost now includes seed, maintenance, and estimated water
  let total-cost1 ((seed + maintenance) * land-size) + water-cost

  let max-revenue 40 * price * land-size ; Assuming 40 units/acre yield
  let max-profit max-revenue - total-cost1 ; Max estimated NET profit


  ; Calculate efficiency: Profit per unit of water required
  let efficiency 0
  if total-water-req > 0 [
    ; Efficiency uses the NET profit against the total water volume required
    set efficiency max-profit / (total-water-req * land-size)
  ]

  ; Report a list: [max-profit, efficiency, total-cost1, total-water-req]
  report (list max-profit efficiency total-cost1 total-water-req)
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
  delete-thefts ; clear from this tick
  set week week + 1
  if week > 26 [ set week 1 ] ; reset week every 26
  update-season ; switch crops if new season
  check-environment ; decide flood/drought/heavy-rain
  update-water-flow ; set water flow based on season and rainfall
  apply-environment-effects ; apply crop damage from events
  update-land ; update farmland color/stage
  allocate-water ; distribute water to farmers based on availability
  deduct-weekly-water-fees
  deduct-living-cost
  ask farmers [ update-strategy ]
  share-water ; farmers request/share water with their connections
  attempt-theft ; farmers attempt to steal water
  update-theft-links ; visualise theft amounts
  detect-thefts ; check for thefts
  update-friendships
  ask farmers [ grow-crops ] ; update crop growth and quality
  show-wealth
  show-social-credit
  show-robbed
  show-shares
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
  if r < flood-prob [
    set current-event "flood"
    set rainfall-factor (1.5 + random-float 0.8) ; 1.5–2.3× flow
    set growth-efficiency 0.8 ; waterlogging => less effective growth now
  ]
  if r >= flood-prob and r < flood-prob + heavy-rain-prob [
    set current-event "heavy-rain"
    set rainfall-factor (1.2 + random-float 0.5) ; 1.2–1.7× flow
    set growth-efficiency 0.9 ; some waterlogging reduces effective growth
  ]
  if r >= flood-prob + heavy-rain-prob and r < flood-prob + heavy-rain-prob + drought-prob [
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
  if season = "kharif" [ set season-factor 1.3 ]
  if season = "rabi"   [ set season-factor 0.7 ]
  set total-flow base-flow * season-factor ; base flow * season factor
  set total-flow total-flow * rainfall-factor ; apply rainfall/drought factor
  set total-flow total-flow * (0.8 + random-float 0.4) ; random fluctuation
  if total-flow < 0 [ set total-flow 0 ]
end

to allocate-water
  let water-per-acre total-flow / total-land; total water available to distribute
  ask farmers [
    ifelse crop-stage < 0 [ set required-water 0 ] ; not growing yet, will start later
    [
      ifelse 1 + crop-stage >= length crop-water-profile [ set required-water 0 ] ; done harvesting, don't need water
      [
        let idx1 int crop-stage
        let idx2 idx1 + 1
        let wei crop-stage - idx1
        let w-req (wei * item idx2 crop-water-profile) + ((1 - wei) * item idx1 crop-water-profile)
        set required-water land-size * w-req ; water needed for this farmer's land & crop stage -> interpolate according to the stages i am in between

        ; --- optional: cap max water per crop type ---
        let max-water 0
        if crop-type = "rice" [ set max-water 5 ]       ; acre-feet per acre
        if crop-type = "wheat" [ set max-water 1.2 ]
        if crop-type = "cotton" [ set max-water 3.5 ]
        if crop-type = "mustard" [ set max-water 3 ]
        if required-water > max-water * land-size [ set required-water max-water * land-size ]
      ]
    ]
    ;set required-water land-size * item crop-stage crop-water-profile
    let loss-factor 1 - (0.01 * ycor); more loss further downstream -> higher ycor. for 32 pos, 32% water loss
    set available-water land-size * water-per-acre * (loss-factor + (random-float water-randomness) - (water-randomness / 2)) ; get water as per land (and loss w/ some randomness)
  ]
end

to deduct-weekly-water-fees
  ; total available-water (allocated water) is billed weekly
  ask farmers [
    ; Assuming 'base-water-cost-per-unit' is a user-defined Global Slider
    let cost available-water * base-water-cost-per-unit
    set wealth wealth - cost
  ]
end

to deduct-living-cost
  ask farmers [
    set wealth wealth - living-cost
  ]
end

to share-water
  ask farmers [ set shared-now 0 ]  ; reset sharing amount

  ask farmers [
    let deficit required-water - available-water
    if deficit <= 0 [ stop ]  ; skip if no need

    ;; --- Step 1: Buy water from friends first (UNMODIFIED) ---
    let friends sort friendship-neighbors  ;; convert agentset to list for foreach
    ;; sort by friendship strength descending
    set friends sort-by [[?1 ?2] -> ([strength] of friendship ([who] of self) ([who] of ?1)) > ([strength] of friendship ([who] of self) ([who] of ?2))] friends

    foreach friends [
      friend ->
      let friend-surplus max (list 0 ([available-water] of friend - [required-water] of friend))
      if friend-surplus > 0 and deficit > 0 [
        let friend-link friendship ([who] of self) ([who] of friend)

        ;; free water if extremely high friendship
        ifelse [strength] of friend-link >= 0.95 [
          let amount-to-get min (list friend-surplus deficit)
          set available-water available-water + amount-to-get
          ask friend [ set available-water available-water - amount-to-get ]
          set deficit required-water - available-water
          set num-trades num-trades + 1
        ]
        ;; otherwise buy water (price scaled by friend's land size)
         [
          let price-per-acre base-water-cost-per-unit
          let amount-to-buy min (list friend-surplus deficit)
          let cost amount-to-buy * price-per-acre * [land-size] of friend
          if wealth >= cost [
            set available-water available-water + amount-to-buy
            ask friend [ set available-water available-water - amount-to-buy ]
            set wealth wealth - cost
            ask friend [ set wealth wealth + cost ]
            set deficit required-water - available-water
            set total-trades total-trades + 1
            set trade-volume trade-volume + amount-to-buy
            set num-trades num-trades + 1
          ]
        ]
      ]
    ]

    ;; --- Step 2: Normal sharing attempt if still in deficit (FIXED LOGIC) ---
    set deficit required-water - available-water
    if deficit <= 0 [ stop ]

    let available_ratio available-water / required-water
    let a 8
    let effective-a a + share-aggressiveness ; ***MODIFICATION 1: Adjust 'a' based on strategy***
    let p_ask 1 / (1 + exp(- effective-a * (1 - available_ratio)))  ; low water -> high chance to ask

    let cnt 0
    let limit 5
    while [ random-float 1 < p_ask and cnt < limit and deficit > 0 ] [
      set cnt cnt + 1

      let friend one-of friendship-neighbors
      if friend != nobody [
        ask friend [
          ;; Determine how much I can give
          let my-surplus available-water - required-water
          if my-surplus < 0 [ set my-surplus 0 ]
          let max-give my-surplus * 0.5  ;; never give more than half surplus

          if max-give > 0 [
            ;; get link to requester
            ; 'self' is the donor (friend), 'myself' is the requester
            let friend-link friendship ([who] of myself) ([who] of self)

            ;; acceptance probability depends on friendliness, tie strength, history
            let f friendliness
            let sc [social-credit] of myself
            let str [strength] of friend-link
            let bal [water-a-to-b-balance] of friend-link
            if ([who] of self = [end1] of friend-link) [ set bal (- bal) ]

            let accept-factor (
              base-share +
              w_f * 2 * (f - 0.5) +
              w_str * 2 * (str - 0.5) +
              w_bal * bal +
              w_sc * 0.1 * sc +
              w_def * 1 * (deficit / [required-water] of myself)
            )
            let p_accept 1 / (1 + exp(- accept-factor))

            ifelse random-float 1 < p_accept [
              ;; transfer amount
              let amount min (list max-give deficit)

              ;; 1. Donor (self/friend) gives water and updates shared-now (Positive)
              set available-water available-water - amount
              set shared-now shared-now + amount

              ;; 2. Requester (myself) receives water and updates shared-now (Positive)
              ask myself [
                set available-water available-water + amount
                set num-shares num-shares + 1
              ]

              ;; 3. Handle Payment (Unified Payment Logic)
              ;if str < 0.95 [
              ;  let price-per-acre base-water-cost-per-unit
              ;  let cost amount * price-per-acre * [land-size] of self ; Cost based on friend's land size
              ;  ask myself [ set wealth wealth - cost ] ; Requester (myself) pays
              ;  set wealth wealth + cost ; Donor (friend) receives payment
              ;]

              ;; 4. Update friendship link and social metrics
              ask friend-link [
                ifelse ([who] of myself = [end1] of friend-link)
                [ set water-a-to-b-balance water-a-to-b-balance + amount ]
                [ set water-a-to-b-balance water-a-to-b-balance - amount ]
                set strength min (list 1 (strength + 0.1))
                set color scale-color red (abs water-a-to-b-balance) 1 0
                set total-trades total-trades + 1

                set trade-volume trade-volume + amount
              ]
              ask myself [ set social-credit (social-credit + 0.3) ]
            ]
            [ ask friend-link [ set strength (strength * 0.95) ] ]
          ]
        ]
      ]
      ;; update deficit for next iteration
      set deficit required-water - available-water
      if deficit <= 0 [ stop ]
      set available_ratio available-water / required-water
      set effective-a a + share-aggressiveness ; ***MODIFICATION 2: Adjust 'a' based on strategy***
      set p_ask 1 / (1 + exp(- effective-a * (1 - available_ratio)))
    ]
  ]
end


;========================
; THEFT
;========================

to attempt-theft
  ; let thefts-this-tick []
  ask farmers [ set stolen-now 0 ]

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
        let safe-required max (list required-water 0.0001)  ;; avoid division by zero
        let deficit-ratio remaining-deficit / safe-required  ; would steal if i have more deficit

        let victim-water [available-water] of victim  ; more likely to steal if other person has a lot of water
        let friendly-thief friendliness  ; wouldn't want to steal if i am friendly
        let sc-thief social-credit        ; wouldn't want to steal if i have people's respect -> won't want to harm image
        let sc-victim [social-credit] of victim  ; more likely to steal from people with less social credit
        let victim-wealth [ wealth ] of victim  ; less likely to steal from rich as they can take legal action - ignore for now
        let str 0
        if (friendship-neighbor? victim) [set str [strength] of friendship (who) ([who] of victim)]

        ;; adjust theft probability based on victim land size
        let size-penalty 0.05 * ([land-size] of victim / 10)  ;; bigger farms are harder to steal from

        ;; FEATURES → logistic acceptance P(theft)
        let x (
          p-steal-base +                           ; ***MODIFIED: Use farmer's dynamic base***
          theft_w_def   * deficit-ratio +                      ; my deficit
          theft_w_vwater * (victim-water / 10) +
          theft_w_f     * (-2 * (friendly-thief - 0.5)) +       ; my friendliness
          theft_w_sc    * (- sc-thief / 10) +
          theft_w_vsc   * (- sc-victim / 10) +          ; low social-credit victim easier
          theft_w_str   * (- str)                           ; less likely to steal from friends
          - size-penalty                                   ; less likely to steal from larger farms
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
            set stolen-now stolen-now + amount
            ; *** UPDATED SOCIAL CREDIT PENALTY ***
            set social-credit social-credit - (0.05 + 0.3 * friendliness)
            set friendliness friendliness * 0.85     ;; becomes slightly less kind

            ;; victim loses water
            ask victim [
              set available-water available-water - amount
              set stolen-now stolen-now - amount
              set times-robbed times-robbed + 1
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
            ;set thefts-this-tick lput (list thief victim amount) thefts-this-tick

            ;; update remaining deficit
            set remaining-deficit required-water - available-water
          ]
        ]
      ]
    ]
  ]
end



to update-theft-links
  ask thefts [
    if (amount-stolen > 0) [ set color red]
  ]
end

to detect-thefts
  ask farmers [
    ;; myself is the potential victim, checking for discrepancy against a friend f1
    let safe-land-size max (list land-size 0.0001)
    let my-water available-water / safe-land-size

    ;; pick one friend below me (ycor lower) who is potentially the thief
    let f1 one-of friendship-neighbors with [ ycor < [ycor] of myself ]
    if f1 != nobody [
      ;; friend's water per unit land, avoid division by zero
      let safe-friend-land-size max (list [land-size] of f1 0.0001)
      let est-water [available-water] of f1 / safe-friend-land-size

      ;; adjust suspicion threshold based on friend's (thief's) land size
      let size-suspicion 0.1 * ([land-size] of f1 / 10)  ;; bigger farms increase suspicion on downstream farmers

      ;; suspicious if my ratio is lower than friend's by threshold
      if est-water > 0 [
        if (my-water / est-water) < (1 - suspicion-threshold - size-suspicion) [
          set total-theft-checks total-theft-checks + 1
          set friendliness friendliness * 0.95

          ;; cost of inquiry
          let inquiry-cost 5000
          set wealth wealth - inquiry-cost

          ;; check for incoming theft links (where myself is the victim)
          let theft-links-list sort my-in-thefts

          if empty? theft-links-list [
            ;; No theft detected, increase paranoia (suspicion threshold)
            set suspicion-threshold min (list 0.5 (suspicion-threshold + 0.01))
          ]
          ; ***FIXED LOGIC: Iterate over theft links where self is the victim (my-in-thefts)***
          foreach theft-links-list [
            t-link ->
            if random-float 1 < detection-likelihood [
              ;; t-link: end1 (thief) -> end2 (victim, which is myself)
              let stolen-amount [amount-stolen] of t-link
              let thief [end1] of t-link
              let victim [end2] of t-link  ; This is always 'myself'

              ;; 1. Return stolen water to victim (myself)
              set available-water available-water + stolen-amount
              set times-robbed times-robbed - 1
              set theft-volume theft-volume - stolen-amount
              set suspicion-threshold max (list 0.02 (suspicion-threshold - 0.01)) ; reward for successful detection

              ;; 2. Punish thief (Updated Economic Penalty)
              let economic-penalty base-water-cost-per-unit * stolen-amount * (2 + [land-size] of thief / 10)
              ask thief [
                set wealth wealth - economic-penalty ; double cost + land-size factor
                set available-water available-water - stolen-amount ; confiscate stolen water
                set social-credit max (list -10 (social-credit - 0.3)) ; major social penalty
              ]

              ;; 3. Mark theft as detected
              set detected-thefts detected-thefts + 1

              ;; 4. Delete the link to clear the theft from display/history for this tick
              ask t-link [ die ]
            ]
          ]
        ]
      ]
    ]
  ]
end


to delete-thefts
  ;wait 0.1
  ask thefts [ die ]
end


;========================
; GROWTH & CROP
;========================

to grow-crops
  if revenue > 0 [ stop ] ; NEW: If I have already harvested this season, stop.
  if 1 + crop-stage >= length crop-water-profile [ stop ] ; done with crops for this season
  if crop-stage < 0 [  ; haven't started growing for this season
    set crop-stage crop-stage + 1
    stop
  ]
  let multiplier (available-water / required-water)  ; calculate growth multiplier based on water & global growth factor
  set multiplier max (list 0.8 (min (list multiplier 1.2)))  ; SYNTAX FIX: clamp multiplier to prevent extreme growth/decay
  set crop-quality crop-quality * multiplier  ; update crop quality based on water received and growth efficiency
  set crop-quality max(list 0.3 (min (list 2 crop-quality)))
  set crop-stage crop-stage + multiplier * growth-efficiency  ; advance crop stage -> based on how much water given
  if 1 + crop-stage >= length crop-water-profile [  ; check if crop reached final stage
    set revenue crop-quality * land-size * 40 * harvest-price ; calculate revenue (Yield 40 units/acre * Price). Removed /40.
    ;show "harvested"
    set wealth wealth + revenue ; add revenue to wealth
  ]
end

to update-season
  if week = 1 [  ; every 26 weeks, switch season
    ifelse season = "rabi" [set season "kharif"][set season "rabi"]  ; toggle season

    ; This single call now handles ALL crop assignment, strategic choice,
    ; cost deduction, and initial growth variable setup.
    assign-crops
    ;show "assigned"

    ask farmers [
      if last-flood? [set crop-quality crop-quality * 1.1]  ; apply flood fertility bonus if last season had flood
    ]
    set last-flood? false  ; clear flood flag after applying bonus
  ]
end

;========================
; Update Friendships
;========================

to update-friendships
  ask friendships with [ strength < 0.05 ]
  [
    set dropped-friendships dropped-friendships + 1
    ifelse random-float 1 < 0.5
    [
      ask end1 [
        create-friendship-with one-of other farmers [
          set water-a-to-b-balance 0
          set strength [friendliness] of end1 * [friendliness] of end2
        ]
      ]
    ]
    [
      ask end2 [
        create-friendship-with one-of other farmers [
          set water-a-to-b-balance 0
          set strength [friendliness] of end1 * [friendliness] of end2
        ]
      ]
    ]
    die
  ]
end


;========================
; Farmer Strategy
;========================

to update-strategy
  let required-safe max (list required-water 0.001) ; Added safety check
  let deficit-stress max(list 0 ((required-water - available-water) / required-safe))

  ; --- DYNAMIC ECONOMIC THRESHOLD CALCULATION ---
  ; This calculation ensures the thresholds scale with the farmer's land size and crop choice.

  ; Max revenue assuming best crop quality and yield (40 units/acre is max yield used in grow-crops)
  let max-revenue harvest-price * 40 * land-size

  ; Total seasonal cost is based on seed and maintenance (deducted at assign-crops)
  let total-seasonal-cost total-cost

  ; 1. LOW WEALTH THRESHOLD (High Risk/Survival Threshold):
  ; Farmer is poor if wealth is less than 1.5 times the guaranteed costs.
  let poor-T 1.5 * total-seasonal-cost

  ; 2. HIGH WEALTH THRESHOLD (Security/Investment Threshold):
  ; Farmer is rich if wealth is significantly greater than their best potential revenue.
  let rich-T 2.5 * max-revenue

  ; --- ASSESSMENT FLAGS ---
  let is-poor (wealth < poor-T)
  let is-rich (wealth > rich-T)
  let high-deficit (deficit-stress > 0.2)
  let low-deficit (deficit-stress <= 0.05)

  ; --- STRATEGY ADAPTATION ---

  ; Base P-steal on SC: Farmers with high social credit are more cautious.
  let sc-modifier social-credit / 10
  set p-steal-base base-theft - sc-modifier
  set share-aggressiveness 0 ; Default
  set current-strategy "Baseline" ; <-- NEW: Set default strategy


  if high-deficit [ ; High Deficit (Need Water Now)
    if is-poor [ ; Poor AND desperate -> High Risk/Survival Strategy
      ; High theft risk scaled by deficit stress
      set p-steal-base base-theft + deficit-stress
      set share-aggressiveness 0.8  ; Aggressive sharing/buying
      set friendliness max(list 0.1 (friendliness * 0.98)) ; Friendliness degrades under extreme stress
      set current-strategy "Poor/High-Risk" ; <-- NEW
    ]
    if not is-poor [ ; Not Poor (Medium or Rich) AND desperate -> Buy/Trade Aggressively
      ; Low base theft probability, only increasing slightly if SC is very low/negative -> dealt with in base case

      set share-aggressiveness 1.5 ; Very aggressive sharing/trading
      set friendliness min(list 1 (friendliness + 0.01))
      set current-strategy "Buy/Trade-Aggressive" ; <-- NEW
    ]
  ]

  if low-deficit [
    if is-rich [ ; Low Deficit, Rich -> Social Investment Strategy
      set p-steal-base base-theft - 2 ; Min Theft Risk
      set share-aggressiveness -0.5 ; Less aggressive asking, more focus on GIVING (implied)
      set friendliness min(list 1 (friendliness + 0.02)) ; High Social Investment
      set suspicion-threshold max(list 0.05 (suspicion-threshold - 0.01)) ; Reduced paranoia
      set current-strategy "Social-Investment" ; <-- NEW
    ]
    ; Default behavior for medium wealth/low deficit is the baseline set above.
  ]

  if current-strategy = "Baseline"
  [
    let tmp item 0 strategies-used
    set tmp tmp + 1
    set strategies-used replace-item 0 strategies-used tmp
  ]
  if current-strategy = "Poor/High-Risk"
  [
    let tmp item 1 strategies-used
    set tmp tmp + 1
    set strategies-used replace-item 1 strategies-used tmp
  ]
  if current-strategy = "Buy/Trade-Aggressive"
  [
    let tmp item 2 strategies-used
    set tmp tmp + 1
    set strategies-used replace-item 2 strategies-used tmp
  ]
  if current-strategy = "Social-Investment"
  [
    let tmp item 3 strategies-used
    set tmp tmp + 1
    set strategies-used replace-item 3 strategies-used tmp
  ]
end

to show-wealth
  let m mean [wealth] of farmers
  let s standard-deviation [wealth] of farmers
  ask farmers [
    let k (wealth - m) / s
    ask patch 30 ycor [
      ifelse (k > 0) [ set pcolor scale-color green k -3 8]
      [ set pcolor scale-color red k -8 3]
    ]
  ]
end

to show-social-credit
  let m mean [social-credit] of farmers
  let s standard-deviation [social-credit] of farmers
  ask farmers [
    let k (social-credit - m) / s
    ask patch 31 ycor [
      ifelse (k > 0) [ set pcolor scale-color green k -3 8]
      [ set pcolor scale-color red k -8 3]
    ]
  ]
end

to show-robbed
  let m sum [times-robbed] of farmers
  if m = 0 [ stop ]
  let s standard-deviation [times-robbed] of farmers
  ask farmers [
    let k times-robbed / s
    ask patch 32 ycor [ set pcolor scale-color orange k 0 5]
  ]
end


to show-shares
  let m sum [num-trades + num-shares] of farmers
  if m = 0 [ stop ]
  let s standard-deviation [num-trades + num-shares] of farmers
  ask farmers [
    let k (num-trades + num-shares) / s
    ask patch 33 ycor [ set pcolor scale-color blue k 0 5]
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

to-report gini [vals]
  let sorted sort vals
  let n length sorted
  if n = 0 [ report 0 ]

  let mean-value mean sorted
  if mean-value = 0 [ report 0 ]

  let cumulative 0
  let weighted-sum 0
  let i 1

  foreach sorted [ v ->
    set weighted-sum weighted-sum + i * v
    set i i + 1
  ]

  report ( (2 * weighted-sum) / (n * sum sorted) - (n + 1) / n )
end

to-report report-individual-farmer-data [f]
  report (list
      [ycor] of f           ; Location on the y-axis
      [land-size] of f      ; Land attribute
      [wealth] of f         ; Wealth attribute
      [social-credit] of f  ; Social credit attribute
      [times-robbed] of f   ; Robbing history
      [num-trades + num-shares] of f     ; Share counts
      [crops-used] of f     ; List/string of crops
      [strategies-used] of f; List/string of strategies
    )
end

; For behaviorspace
to-report report-all-farmer-data
  let farmer-list sort-by [ [f1 f2] -> [ycor] of f1 < [ycor] of f2 ] farmers
  report map [
    f -> report-individual-farmer-data f
  ] farmer-list
end
@#$#@#$#@
GRAPHICS-WINDOW
479
17
1082
603
-1
-1
17.5
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
33
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
160.0
5
1
NIL
HORIZONTAL

PLOT
1095
12
1317
184
Water Required
NIL
NIL
0.0
1.0
0.0
10.0
true
false
"" ""
PENS
"default" 0.1 1 -13840069 true "" "histogram [required-water / land-size] of farmers"

PLOT
1096
216
1327
383
Crop Quality
NIL
NIL
0.0
2.5
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
1096
401
1329
580
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
1339
13
1556
185
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
1340
216
1557
387
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
1575
16
1875
385
Thefts
Ticks
Amount
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"Total Thefts" 1.0 0 -13791810 true "" "plot total-thefts\n\n"
"Detected Thefts" 1.0 0 -2674135 true "" "plot detected-thefts"

MONITOR
20
256
176
301
avg friendship strength
mean [strength] of friendships
5
1
11

SLIDER
50
569
222
602
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
700
218
733
w_sc
w_sc
0
3
1.9
0.1
1
NIL
HORIZONTAL

SLIDER
48
610
220
643
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
654
219
687
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
744
218
777
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
525
221
558
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
41
314
124
359
NIL
total-trades
17
1
11

MONITOR
35
367
130
412
NIL
trade-volume
5
1
11

SLIDER
271
755
443
788
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
272
568
444
601
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
273
532
445
565
base-theft
base-theft
-20
20
-1.0
0.1
1
NIL
HORIZONTAL

SLIDER
273
605
445
638
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
272
679
444
712
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
271
717
443
750
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
271
642
443
675
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
195
258
275
303
NIL
total-thefts
17
1
11

MONITOR
178
308
270
353
NIL
theft-volume
5
1
11

MONITOR
175
364
279
409
NIL
detected-thefts
17
1
11

MONITOR
178
419
279
464
sus-threshold
mean [suspicion-threshold] of farmers
5
1
11

SLIDER
48
165
227
198
water-randomness
water-randomness
0
1
0.1
0.1
1
NIL
HORIZONTAL

MONITOR
41
425
124
470
friendliness
mean [friendliness] of farmers
5
1
11

MONITOR
296
257
401
302
NIL
total-theft-checks
17
1
11

SLIDER
238
162
412
195
crop-stage-variance
crop-stage-variance
0
10
4.0
1
1
NIL
HORIZONTAL

SLIDER
273
496
455
529
detection-likelihood
detection-likelihood
0
1
0.75
0.05
1
NIL
HORIZONTAL

PLOT
1096
603
1334
765
Wealth Distribution
ticks
wealth
0.0
5000000.0
0.0
10.0
true
false
"" ""
PENS
"default" 100000.0 1 -955883 true "" "histogram [wealth] of farmers"

SLIDER
501
629
673
662
wheat-price
wheat-price
3000
4000
3500.0
100
1
NIL
HORIZONTAL

SLIDER
501
669
673
702
mustard-price
mustard-price
5000
7000
6000.0
100
1
NIL
HORIZONTAL

SLIDER
503
714
675
747
rice-price
rice-price
4000
5000
4700.0
100
1
NIL
HORIZONTAL

SLIDER
502
759
674
792
cotton-price
cotton-price
7000
10500
9200.0
100
1
NIL
HORIZONTAL

SLIDER
701
630
873
663
wheat-seed-cost
wheat-seed-cost
5000
8500
5800.0
100
1
NIL
HORIZONTAL

SLIDER
702
673
874
706
mustard-seed-cost
mustard-seed-cost
1000
2000
1300.0
100
1
NIL
HORIZONTAL

SLIDER
702
715
874
748
rice-seed-cost
rice-seed-cost
3500
7500
5300.0
100
1
NIL
HORIZONTAL

SLIDER
701
760
873
793
cotton-seed-cost
cotton-seed-cost
4000
15000
8400.0
100
1
NIL
HORIZONTAL

SLIDER
885
629
1083
662
base-maintenance-cost
base-maintenance-cost
60000
150000
80000.0
10000
1
NIL
HORIZONTAL

SLIDER
893
671
1082
704
base-water-cost-per-unit
base-water-cost-per-unit
400
2000
700.0
100
1
NIL
HORIZONTAL

PLOT
1528
406
1903
759
Strategy
Ticks
Number of Farmers
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"Poor/High Risk" 1.0 0 -2674135 true "" "plot count farmers with [current-strategy = \"Poor/High-Risk\"]"
"Buy/Trade-Aggressive" 1.0 0 -14454117 true "" "plot count farmers with [current-strategy = \"Buy/Trade-Aggressive\"]"
"Social-Investment" 1.0 0 -13840069 true "" "plot count farmers with [current-strategy = \"Social-Investment\"]"
"Baseline" 1.0 0 -16777216 true "" "plot count farmers with [current-strategy = \"Baseline\"]"

TEXTBOX
703
602
892
640
This is all related to Wealth
15
0.0
1

TEXTBOX
65
484
215
522
This is all related to theft/sharing water
15
0.0
1

TEXTBOX
246
79
431
131
General setup commands for the world
15
0.0
1

PLOT
1347
601
1526
762
Wealth Variance
NIL
NIL
0.0
10.0
0.0
1.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "if sum [wealth] of farmers > 0 [ plot standard-deviation [wealth] of farmers ]"

PLOT
1341
405
1521
578
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
9
213
123
246
flood-prob
flood-prob
0
1
0.01
0.01
1
NIL
HORIZONTAL

SLIDER
132
214
271
247
heavy-rain-prob
heavy-rain-prob
0
1 - flood-prob
0.05
0.01
1
NIL
HORIZONTAL

SLIDER
279
214
410
247
drought-prob
drought-prob
0
1 - flood-prob - heavy-rain-prob
0.05
0.01
1
NIL
HORIZONTAL

SLIDER
879
711
1089
744
base-living-cost-month
base-living-cost-month
0
100000
20000.0
1000
1
NIL
HORIZONTAL

MONITOR
416
255
473
300
NIL
season
17
1
11

MONITOR
286
363
367
408
min wealth
min [wealth] of farmers
0
1
11

MONITOR
378
364
460
409
max wealth
max [wealth] of farmers
0
1
11

MONITOR
287
310
426
355
NIL
dropped-friendships
17
1
11

MONITOR
329
416
410
461
avg wealth
mean [wealth] of farmers
0
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
<experiments>
  <experiment name="standard" repetitions="200" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <metric>total-land</metric>
    <metric>mean [wealth] of farmers</metric>
    <metric>standard-deviation [wealth] of farmers</metric>
    <metric>theft-volume</metric>
    <metric>trade-volume</metric>
    <metric>mean [strength] of friendships</metric>
    <metric>mean [social-credit] of farmers</metric>
    <metric>report-all-farmer-data</metric>
    <enumeratedValueSet variable="rice-seed-cost">
      <value value="5300"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="drought-prob">
      <value value="0.05"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="base-maintenance-cost">
      <value value="80000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="w_sc">
      <value value="1.9"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="w_def">
      <value value="1.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="base-share">
      <value value="3"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-farmers">
      <value value="33"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="w_bal">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="base-theft">
      <value value="-1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="detection-likelihood">
      <value value="0.75"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="cotton-price">
      <value value="9200"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="mustard-price">
      <value value="6000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="theft_w_vwater">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="crop-stage-variance">
      <value value="4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="theft_w_f">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wheat-price">
      <value value="3500"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="w_str">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="cotton-seed-cost">
      <value value="8400"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="heavy-rain-prob">
      <value value="0.05"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="rice-price">
      <value value="4700"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="base-living-cost-month">
      <value value="20000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="theft_w_sc">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="w_f">
      <value value="1.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="mustard-seed-cost">
      <value value="1300"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="flood-prob">
      <value value="0.01"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="theft_w_vsc">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="base-flow">
      <value value="160"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="theft_w_str">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wheat-seed-cost">
      <value value="5800"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="water-randomness">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="base-water-cost-per-unit">
      <value value="600"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="theft_w_def">
      <value value="1.5"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="vary-flow" repetitions="100" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <metric>total-land</metric>
    <metric>mean [wealth] of farmers</metric>
    <metric>standard-deviation [wealth] of farmers</metric>
    <metric>theft-volume</metric>
    <metric>trade-volume</metric>
    <metric>mean [strength] of friendships</metric>
    <metric>mean [social-credit] of farmers</metric>
    <metric>report-all-farmer-data</metric>
    <enumeratedValueSet variable="rice-seed-cost">
      <value value="5300"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="drought-prob">
      <value value="0.05"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="base-maintenance-cost">
      <value value="80000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="w_sc">
      <value value="1.9"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="w_def">
      <value value="1.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="base-share">
      <value value="3"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-farmers">
      <value value="33"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="w_bal">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="base-theft">
      <value value="-1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="detection-likelihood">
      <value value="0.75"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="cotton-price">
      <value value="9200"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="mustard-price">
      <value value="6000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="theft_w_vwater">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="crop-stage-variance">
      <value value="4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="theft_w_f">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wheat-price">
      <value value="3500"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="w_str">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="cotton-seed-cost">
      <value value="8400"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="rice-price">
      <value value="4700"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="heavy-rain-prob">
      <value value="0.05"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="base-living-cost-month">
      <value value="20000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="theft_w_sc">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="w_f">
      <value value="1.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="mustard-seed-cost">
      <value value="1300"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="flood-prob">
      <value value="0.01"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="theft_w_vsc">
      <value value="2"/>
    </enumeratedValueSet>
    <steppedValueSet variable="base-flow" first="100" step="60" last="280"/>
    <enumeratedValueSet variable="theft_w_str">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wheat-seed-cost">
      <value value="5800"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="water-randomness">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="base-water-cost-per-unit">
      <value value="700"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="theft_w_def">
      <value value="1.5"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="vary-water-randomness" repetitions="100" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <metric>water-randomness</metric>
    <metric>mean [wealth] of farmers</metric>
    <metric>standard-deviation [wealth] of farmers</metric>
    <metric>theft-volume</metric>
    <metric>trade-volume</metric>
    <metric>mean [strength] of friendships</metric>
    <metric>mean [social-credit] of farmers</metric>
    <metric>report-all-farmer-data</metric>
    <enumeratedValueSet variable="rice-seed-cost">
      <value value="5300"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="drought-prob">
      <value value="0.05"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="base-maintenance-cost">
      <value value="80000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="w_sc">
      <value value="1.9"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="w_def">
      <value value="1.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="base-share">
      <value value="3"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-farmers">
      <value value="33"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="w_bal">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="base-theft">
      <value value="-1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="detection-likelihood">
      <value value="0.75"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="cotton-price">
      <value value="9200"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="mustard-price">
      <value value="6000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="theft_w_vwater">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="crop-stage-variance">
      <value value="4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="theft_w_f">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wheat-price">
      <value value="3500"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="w_str">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="cotton-seed-cost">
      <value value="8400"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="rice-price">
      <value value="4700"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="heavy-rain-prob">
      <value value="0.05"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="base-living-cost-month">
      <value value="20000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="theft_w_sc">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="w_f">
      <value value="1.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="mustard-seed-cost">
      <value value="1300"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="flood-prob">
      <value value="0.01"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="theft_w_vsc">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="base-flow">
      <value value="160"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="theft_w_str">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wheat-seed-cost">
      <value value="5800"/>
    </enumeratedValueSet>
    <steppedValueSet variable="water-randomness" first="0" step="0.1" last="0.4"/>
    <enumeratedValueSet variable="base-water-cost-per-unit">
      <value value="700"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="theft_w_def">
      <value value="1.5"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="vary-crop-stage-variance" repetitions="100" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <metric>crop-stage-variance</metric>
    <metric>mean [wealth] of farmers</metric>
    <metric>standard-deviation [wealth] of farmers</metric>
    <metric>theft-volume</metric>
    <metric>trade-volume</metric>
    <metric>mean [strength] of friendships</metric>
    <metric>mean [social-credit] of farmers</metric>
    <metric>report-all-farmer-data</metric>
    <enumeratedValueSet variable="rice-seed-cost">
      <value value="5300"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="drought-prob">
      <value value="0.05"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="base-maintenance-cost">
      <value value="80000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="w_sc">
      <value value="1.9"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="w_def">
      <value value="1.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="base-share">
      <value value="3"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-farmers">
      <value value="33"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="w_bal">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="base-theft">
      <value value="-1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="detection-likelihood">
      <value value="0.75"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="cotton-price">
      <value value="9200"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="mustard-price">
      <value value="6000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="theft_w_vwater">
      <value value="1"/>
    </enumeratedValueSet>
    <steppedValueSet variable="crop-stage-variance" first="0" step="2" last="8"/>
    <enumeratedValueSet variable="theft_w_f">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wheat-price">
      <value value="3500"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="w_str">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="cotton-seed-cost">
      <value value="8400"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="rice-price">
      <value value="4700"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="heavy-rain-prob">
      <value value="0.05"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="base-living-cost-month">
      <value value="20000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="theft_w_sc">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="w_f">
      <value value="1.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="mustard-seed-cost">
      <value value="1300"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="flood-prob">
      <value value="0.01"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="theft_w_vsc">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="base-flow">
      <value value="160"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="theft_w_str">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wheat-seed-cost">
      <value value="5800"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="water-randomness">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="base-water-cost-per-unit">
      <value value="700"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="theft_w_def">
      <value value="1.5"/>
    </enumeratedValueSet>
  </experiment>
</experiments>
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
