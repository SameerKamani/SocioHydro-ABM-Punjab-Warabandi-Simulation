# Socio-Hydrological Modeling of Cooperative and Competitive Water Use in Punjab's Traditional Irrigation Networks

![System Flow Diagram](path/to/system-flow-diagram.png)  
*(Figure 1 from the ODD: System flow diagram illustrating the core components and process structure of the agent-based irrigation model. Replace with actual image path if available.)*

## Overview

This repository contains an agent-based model (ABM) implemented in NetLogo to simulate farmer behavior in Warabandi canal irrigation systems, as commonly used in Punjab, Pakistan, and other parts of South Asia. The model explores how farmers deviate from formal rotational water allocation rules through informal mechanisms like water sharing, monetary trades, and theft. It integrates social, economic, hydrological, and environmental factors to investigate the conditions under which cooperative governance is sustained or undermined, leading to patterns in agricultural performance, economic inequality, and social capital.

The model is grounded in socio-hydrological theory and empirical data from Punjab's irrigation contexts. It reproduces key emergent patterns, such as upstream advantages, theft spikes during scarcity, and erosion of social networks under repeated conflicts.

**Authors**: Sameer Kamani¹ and Musab Kasbati¹  
¹Modeling Social Complexity — Fall 2025, Habib University, Karachi, Pakistan

**Date**: Fall 2025 (Model developed as part of a course project)

## Purpose

The primary goal is to examine the interplay of:
- Landholding inequality and upstream-downstream positioning.
- Social relationships (friendships for sharing/trading).
- Economic constraints (wealth, costs, crop choices).
- Hydrological variability (seasons, floods, droughts, random fluctuations).

By simulating these feedbacks, the model identifies scenarios where cooperation thrives (e.g., balanced trading in abundance) or breaks down (e.g., increased theft and inequality under scarcity).

## Expected Emergent Patterns

From individual rules, the model generates macro-level outcomes, including:
- Persistent wealth accumulation by upstream and large landholders due to lower losses and theft exposure.
- Increased water theft during low flow, droughts, or high variability.
- Higher sharing/trading when crop stages are staggered.
- Adoption of high-risk strategies (e.g., theft) by downstream/small farmers under chronic deficits.
- Erosion of social networks (declining strength, credit, and ties) from imbalanced exchanges or theft.
- Infrequent but severe theft punishments, allowing low-level extraction to persist.
- Accelerated wealth inequality (higher Gini coefficients) under scarce/variable water.
- Stronger cooperation during abundant seasons or synchronized cropping.

## Features

- **Agents**: Heterogeneous farmers with attributes like land size, wealth, social credit, friendliness, crop type/stage/quality, water needs, and adaptive strategies.
- **Social Networks**: Undirected friendships for sharing/trading (with strength and balance); directed theft links (temporary).
- **Environment**: Linear canal with downstream losses; probabilistic events (floods, heavy rain, droughts).
- **Seasons and Crops**: Alternates between Rabi (wheat, mustard) and Kharif (rice, cotton) every 26 weeks; strategic crop choice based on wealth/profit/efficiency.
- **Behaviors**: Water allocation, sharing (gifts/purchases/requests), theft (probabilistic, upstream-to-downstream), detection/punishment, network evolution.
- **Economics**: Costs (seeds, maintenance, water fees, living); revenue from harvests; wealth updates.
- **Strategies**: Weekly adaptation to 4 classes (Baseline, Poor/High-Risk, Buy/Trade-Aggressive, Social-Investment) based on deficit and wealth.
- **Scales**: Spatial (1 patch = 1 acre); Temporal (1 tick = 1 week); Duration (520 ticks = 10 years).
- **Stochasticity**: Randomness in initials, events, allocations, decisions for realism.

## Installation and Requirements

This model is built in NetLogo (version 6.x or later recommended).

1. Download and install [NetLogo](https://ccl.northwestern.edu/netlogo/) (free and open-source).
2. Clone this repository:
   ```
   git clone https://github.com/your-repo/socio-hydrological-irrigation-model.git
   ```
3. Open the `.nlogo` file (e.g., `irrigation-model.nlogo`) in NetLogo.

No additional dependencies are required, as NetLogo handles all simulations internally.

## Usage

1. **Interface Overview**:
   - **Sliders**: Adjust parameters like `num-farmers` (default: 33), `base-flow` (default: 160 acre-feet/week), crop prices, event probabilities, and logistic weights.
   - **Buttons**: `setup` to initialize; `go` to run (or toggle forever for continuous simulation).
   - **Monitors**: Real-time metrics (e.g., total-thefts, trade-volume, avg friendship strength).
   - **Plots**: Time-series (e.g., Water Required, Social Credits, Thefts) and distributions (e.g., Wealth, Strategies).

   ![NetLogo Interface](path/to/interface-screenshot.png)  
   *(Figure 2 from the ODD: NetLogo model interface showing real-time monitors and plots. Replace with actual image path if available.)*

2. **Running the Model**:
   - Click `setup` to initialize farmers, networks, and environment.
   - Adjust sliders for experiments (e.g., vary `base-flow` for scarcity scenarios).
   - Click `go` to simulate weekly ticks.
   - Observe patterns over 520 ticks.

3. **Experiments**:
   - Use NetLogo's BehaviorSpace for batch runs (e.g., vary `base-flow` from 40–450 to analyze scarcity impacts).
   - Export data via reporters like `report-all-farmer-data` for analysis (wealth, strategies, etc.).

4. **Example Scenarios** (from ODD Outputs):
   - **High Base Flow (450)**: Low theft (0), high trades (73), stable networks (0 dropped friendships), positive wealth growth.
   - **Medium Base Flow (160)**: Moderate theft (524), trades (810), some network erosion (12 dropped).
   - **Low Base Flow (40)**: High theft (1603), fewer trades (633), severe erosion (189 dropped), negative average wealth.

## Model Components

### Entities
- **Farmers**: Positioned upstream-to-downstream; own land, wealth, crops, water, strategies.
- **Friendships**: Undirected links with strength and water balance.
- **Thefts**: Directed links for stolen amounts (cleared weekly).
- **Patches**: Canal (visual); farmland colored by crop stage; side visuals for wealth/social metrics.

### Processes (Weekly Sequence)
1. Seasonal update & crop assignment.
2. Environmental events.
3. Water supply & allocation (with losses).
4. Economic deductions.
5. Strategy update.
6. Water sharing & trading.
7. Water theft.
8. Theft detection & punishment.
9. Network evolution.
10. Crop growth & harvest.

Detailed submodels (e.g., logistic probabilities for sharing/theft) are in the ODD and code.

## Parameters

All parameters are adjustable via sliders. Defaults reflect Punjab conditions:

| Parameter                  | Default | Range      | Description (units) |
|----------------------------|---------|------------|---------------------|
| num-farmers                | 33     | 10–33     | Number of farming households |
| base-flow                  | 160    | 50–500    | Baseline canal inflow (acre-feet/week) |
| water-randomness           | 0.10   | 0–0.40    | Random weekly fluctuation in allocation |
| crop-stage-variance        | 4      | 0–8       | Max initial stagger in planting dates (weeks) |
| flood-prob                 | 0.01   | 0–0.10    | Probability of flood event |
| heavy-rain-prob            | 0.05   | 0–0.20    | Probability of heavy rainfall event |
| drought-prob               | 0.05   | 0–0.25    | Probability of drought event |
| rice-price / seed-cost     | 4700 / 5300 | 4000–7000 | Price per 40-kg bag / seed cost per acre (PKR) |
| ... (see ODD Table 1 for full list) | ...    | ...       | ... |

## Outputs and Observation

- **Monitors**: Aggregate counters (thefts, trades, checks, dropped friendships); averages (strength, friendliness, suspicion); min/max/avg wealth; season/total-land.
- **Plots**: Time-series (Water Required, Crop Quality, Social Credits, Incoming Water, Friendship Balance, Thefts); Distributions (Wealth, Wealth Variance, Strategies).
- **Exports**: Use BehaviorSpace for time-series and final stats (e.g., Gini for inequality).

## Limitations

- Simplified hydrology (linear losses, no groundwater).
- Fixed crop prices (no market dynamics).
- No external policies or cultural factors.
- Bounded to 520 ticks; assumes no migration or hierarchies.

## References

See the ODD document for full citations, including socio-hydrology papers and Punjab irrigation studies.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

For questions or contributions, contact the authors at Sameerkamani03@gmail.com or mk07811@st.habib.edu.pk .
