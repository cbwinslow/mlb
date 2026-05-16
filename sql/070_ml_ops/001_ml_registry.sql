BEGIN;

CREATE SCHEMA IF NOT EXISTS ml;
CREATE SCHEMA IF NOT EXISTS ops;

CREATE TABLE IF NOT EXISTS ml.problem_definition (
    problem_definition_id BIGSERIAL PRIMARY KEY,
    problem_code TEXT NOT NULL UNIQUE,
    problem_name TEXT NOT NULL,
    target_grain TEXT NOT NULL,
    target_type TEXT NOT NULL,
    target_description TEXT,
    prediction_horizon TEXT,
    label_sql TEXT,
    business_goal TEXT,
    active_flag BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE ml.problem_definition IS
    'Defines prediction problems such as moneyline, totals, strikeout props, hit props, or next-pitch outcome forecasting.';

CREATE TABLE IF NOT EXISTS ml.feature_set (
    feature_set_id BIGSERIAL PRIMARY KEY,
    feature_set_code TEXT NOT NULL UNIQUE,
    feature_set_name TEXT NOT NULL,
    entity_grain TEXT NOT NULL,
    description TEXT,
    owner_name TEXT,
    is_realtime_compatible BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE ml.feature_set IS
    'Logical grouping of features, for example pitcher rolling form, team offense form, bullpen fatigue, or pitch-level context.';

CREATE TABLE IF NOT EXISTS ml.feature_definition (
    feature_definition_id BIGSERIAL PRIMARY KEY,
    feature_set_id BIGINT NOT NULL
        REFERENCES ml.feature_set(feature_set_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    feature_name TEXT NOT NULL,
    feature_data_type TEXT NOT NULL,
    feature_grain TEXT NOT NULL,
    source_layer TEXT NOT NULL,
    source_object_name TEXT,
    derivation_sql TEXT,
    derivation_python_ref TEXT,
    default_fill_strategy TEXT,
    null_rate_expectation NUMERIC(8,5),
    feature_description TEXT,
    active_flag BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT ml_feature_definition_unique
        UNIQUE (feature_set_id, feature_name)
);

COMMENT ON TABLE ml.feature_definition IS
    'Catalog of individual model features, their grain, source, and derivation logic.';

CREATE TABLE IF NOT EXISTS ml.model_family (
    model_family_id BIGSERIAL PRIMARY KEY,
    model_family_code TEXT NOT NULL UNIQUE,
    model_family_name TEXT NOT NULL,
    algorithm_class TEXT NOT NULL,
    supports_probability_output BOOLEAN NOT NULL DEFAULT FALSE,
    supports_multiclass BOOLEAN NOT NULL DEFAULT FALSE,
    supports_online_update BOOLEAN NOT NULL DEFAULT FALSE,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE ml.model_family IS
    'Model family registry for logistic regression, random forest, gradient boosting, neural network, Bayesian, Markov, ensemble, and simulation approaches.';

CREATE TABLE IF NOT EXISTS ml.model_definition (
    model_definition_id BIGSERIAL PRIMARY KEY,
    problem_definition_id BIGINT NOT NULL
        REFERENCES ml.problem_definition(problem_definition_id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,
    model_family_id BIGINT NOT NULL
        REFERENCES ml.model_family(model_family_id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,
    feature_set_id BIGINT
        REFERENCES ml.feature_set(feature_set_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    model_code TEXT NOT NULL UNIQUE,
    model_name TEXT NOT NULL,
    model_version TEXT NOT NULL,
    training_framework TEXT,
    hyperparameters_json JSONB,
    search_space_json JSONB,
    training_script_ref TEXT,
    artifact_uri TEXT,
    is_ensemble BOOLEAN NOT NULL DEFAULT FALSE,
    ensemble_method TEXT,
    parent_model_definition_id BIGINT
        REFERENCES ml.model_definition(model_definition_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    status_code TEXT NOT NULL DEFAULT 'draft',
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE ml.model_definition IS
    'Versioned model registry supporting single models, stacked models, and ensemble definitions.';

INSERT INTO ml.model_family (
    model_family_code,
    model_family_name,
    algorithm_class,
    supports_probability_output,
    supports_multiclass,
    supports_online_update,
    notes
)
VALUES
    ('logreg', 'Logistic Regression', 'generalized_linear_model', TRUE, TRUE, FALSE, 'Common baseline for interpretable baseball forecasting.'),
    ('rf', 'Random Forest', 'tree_ensemble', TRUE, TRUE, FALSE, 'Useful nonlinear baseline for tabular baseball features.'),
    ('gbm', 'Gradient Boosting', 'boosted_tree_ensemble', TRUE, TRUE, FALSE, 'Strong tabular learner for structured prediction tasks.'),
    ('nn', 'Neural Network', 'neural_network', TRUE, TRUE, TRUE, 'Flexible function approximator for high-dimensional signals.'),
    ('svm', 'Support Vector Machine', 'kernel_method', FALSE, TRUE, FALSE, 'Sometimes useful for classification boundaries.'),
    ('bayes', 'Bayesian Model', 'bayesian', TRUE, TRUE, TRUE, 'Supports posterior uncertainty and updating workflows.'),
    ('markov', 'Markov Model', 'state_space', TRUE, FALSE, TRUE, 'Good fit for inning/run-state and transition simulation.'),
    ('ensemble', 'Ensemble', 'ensemble', TRUE, TRUE, TRUE, 'Stacking, blending, and voting approaches.'),
    ('simulation', 'Simulation Engine', 'simulation', TRUE, FALSE, TRUE, 'Monte Carlo and state-transition simulation frameworks.')
ON CONFLICT (model_family_code) DO NOTHING;

COMMIT;