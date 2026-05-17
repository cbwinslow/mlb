# MLB Analytics Platform Modeling

## Purpose

This document defines the modeling design for the MLB analytics platform. Unlike the architecture document, which explains the overall system structure, unlike the data dictionary, which explains where objects live, unlike the security document, which explains access control, and unlike the ingestion document, which explains how source data arrives, this file explains how predictive, analytical, and simulation workflows should be represented once data is already in the platform.

The platform is not being designed for one single model. It is being designed as a reusable modeling environment for baseball analytics, sabermetrics, historical forecasting, game predictions, player props, live updates, and future agent-assisted analysis.

## Modeling goals

The modeling layer is meant to support these goals:

- Represent different prediction problems explicitly.
- Support multiple modeling grains.
- Preserve feature lineage and point-in-time correctness.
- Separate definition objects from execution objects.
- Support backtesting and live scoring from the same platform.
- Track evaluation and simulation as first-class workflows.
- Keep workspace ownership for private models and experiments.
- Allow future app, API, and agent surfaces to query model outputs safely.

## Modeling scope

The modeling layer should support several kinds of work, not just one prediction style.

### Core prediction use cases

- pregame moneyline or winner prediction,
- run total prediction,
- player prop probabilities,
- hit or strikeout event probabilities,
- team scoring expectation,
- inning or live-state updates,
- ranking and comparative evaluation workflows.

### Analytical use cases

- feature importance comparison,
- rolling performance diagnostics,
- model drift inspection,
- historical era comparisons,
- source sensitivity testing,
- calibration analysis.

### Simulation use cases

- game outcome simulation,
- player outcome simulation,
- market scenario testing,
- sensitivity analysis,
- distribution forecasting instead of point estimates only.

## Modeling grains

A major design choice is that the platform should support multiple grains of prediction. Different questions require different observation levels.

### Pitch grain

For tasks like next-pitch behavior, whiff likelihood, strike probability, or pitch classification, the natural grain is one pitch.

### Plate appearance grain

For tasks like strikeout probability, hit probability, walk probability, or batted-ball outcome, the natural grain is one plate appearance.

### Game grain

For tasks like winner prediction, totals, spread-like baseball proxies, or game-level simulations, the natural grain is one game.

### Aggregated player/team grain

For rolling windows, player-day, team-day, or matchup-window tasks, the natural grain may be a derived observation rather than a native event row.

The schema should not force all modeling through one grain, because that would make some important use cases awkward or lossy.

## Core modeling objects

The `ml` schema is structured around several object families.

### Problem definitions

A problem definition identifies what is being predicted. This matters because model logic, evaluation logic, and downstream consumers depend on the target being explicit.

Examples:
- home team win probability,
- pitcher strikeout over probability,
- batter hit probability,
- next inning run scored,
- rest-of-game win probability.

### Feature sets and feature definitions

A feature set is a managed collection of features intended to be used together. A feature definition describes one feature, where it comes from, and what it means.

This is important because serious modeling projects fail when features exist only inside notebooks or ad hoc scripts. The platform should preserve feature meaning and lineage as durable metadata.

### Feature snapshots

A feature snapshot stores the point-in-time feature values used for training or scoring. This is critical because many baseball features are time-sensitive. If a model is trained using future information by accident, the results become misleading.

Feature snapshots should therefore be treated as historical evidence of what the model knew at a given scoring or training moment.

### Dataset definitions

A dataset definition describes how a model-ready dataset is assembled. It is the reusable recipe, not the run itself.

This should include ideas like:
- source scope,
- observation grain,
- eligible seasons or windows,
- target definition,
- feature-set linkage,
- label timing rules,
- filtering criteria.

### Dataset splits

A dataset split stores how the data was divided for evaluation. This is a first-class concept because walk-forward validation, holdout testing, and rolling-window testing are essential for sports prediction work.

### Model families

A model family records the general algorithm category rather than one specific trained instance.

Examples:
- logistic regression,
- gradient boosting,
- random forest,
- neural network,
- Bayesian model,
- Markov/state-space model,
- ensemble.

### Model definitions

A model definition is the durable record of one model configuration or version. It should capture the relationship between a model family, a prediction problem, a dataset recipe, and any relevant hyperparameter or framework metadata.

### Training runs

A training run is one actual execution of model training. It is not the same thing as the model definition. A model definition says what the model is; a training run says when and how a concrete training execution happened.

### Prediction runs

A prediction run records one scoring event or batch of scoring events. This is different from training because scoring may happen repeatedly on new data using the same model definition.

### Prediction outputs

Prediction outputs are row-level results tied to a prediction run. These should contain the scored probabilities, values, or other outputs that later surfaces can consume.

### Prediction evaluations

An evaluation record links predictions to realized outcomes and metrics. This is necessary for ranking models, checking calibration, and seeing whether a prediction process is actually useful.

### Backtest runs

A backtest run represents a historical evaluation workflow. It should be treated as its own first-class object because backtests often have different logic and reporting needs than one-off prediction runs.

### Simulation runs

A simulation run represents repeated scenario generation or probabilistic outcome generation. This deserves separate treatment because simulation often produces distributions and scenario sets instead of one prediction row per observation.

## Definition objects vs execution objects

One of the most important modeling design choices is separating stable definitions from runtime executions.

### Definition-oriented objects

These describe durable concepts:
- problem definitions,
- feature definitions,
- feature sets,
- dataset definitions,
- model families,
- model definitions.

### Execution-oriented objects

These describe things that happened:
- feature snapshots,
- dataset splits,
- training runs,
- prediction runs,
- prediction outputs,
- evaluations,
- backtests,
- simulations.

This separation is what makes the platform auditable and reusable instead of just becoming a pile of experiment artifacts.

## Point-in-time correctness

Point-in-time correctness is especially important in sports prediction. A feature set that uses information not actually available at prediction time will overstate performance and damage model credibility.

The platform should therefore prefer:
- explicit feature snapshot timestamps,
- documented label timing rules,
- evaluation windows that mirror real deployment timing,
- versioned dataset definitions instead of hidden notebook assumptions.

## Workspace ownership

The modeling layer should support workspace ownership because models, training runs, backtests, and predictions are often private intellectual property even when the baseball facts behind them are global.

This allows multiple teams or users to share one canonical baseball warehouse while still keeping their modeling work isolated.

## Supported modeling styles

The registry should be broad enough to support:
- classical statistics,
- tabular machine learning,
- hierarchical or Bayesian methods,
- ensemble workflows,
- probabilistic simulation,
- live updating models,
- rule-based benchmark models.

That flexibility matters because sports analytics systems usually mature through multiple layers of baselines, blends, overrides, and recalibration rather than one permanent algorithm choice.

## Evaluation philosophy

A useful modeling platform does more than store predictions. It should support comparison and accountability.

Important evaluation concepts include:
- out-of-sample accuracy,
- calibration,
- log loss or probabilistic scoring quality,
- ROI-style downstream evaluation,
- model-vs-model ranking,
- strategy-specific backtest outcomes.

The schema does not need to force one metric, but it should make it easy to store many metrics in a structured way.

## Relationship to downstream consumers

The modeling layer should serve several downstream consumers:
- APIs that return predictions,
- dashboards showing recent scores and model performance,
- agents that query model outputs or evaluations,
- human workflows that compare models and runs,
- alerting systems that act on thresholds or changes.

This is why prediction outputs and evaluations should be durable records, not just temporary Python objects.

## Immediate next modeling tasks

The next modeling-focused implementation tasks should be:

1. confirm the final `ml` table inventory,
2. define the first prediction problems to support,
3. decide which feature metadata belongs in SQL vs artifact storage,
4. define how prediction outputs are keyed and linked to observations,
5. define evaluation metric storage conventions,
6. define which modeling objects are workspace-scoped from day one.