"""
Parameters for the `CoverProblem` (Optimal Enriched-Set Cover).
"""
immutable CoverParams
    a::Float64 # prior probability of covered element to be unmasked
    b::Float64 # prior probability of uncovered element to be masked
    reg::Float64 # regularizing multiplier for w[i]*w[i], penalizes non-zero weights
    min_weight::Float64 # minimal non-zero set probability

    function CoverParams(a::Number, b::Number, reg::Number = 0.01, min_weight::Number = 1E-2)
        (0.0 < a < 1.0) || throw(ArgumentError("`a` must be within (0,1) range"))
        (0.0 < b < 1.0) || throw(ArgumentError("`b` must be within (0,1) range"))
        (reg >= 0.0) || throw(ArgumentError("`reg` must be non-negative"))
        (0.0 < min_weight <= 1.0) || throw(ArgumentError("`min_weight` must be within (0,1) range"))
        (1.0-a > b) || warn("Incoherent parameters: covered element is less likely ($(1-a)) to be observed than uncovered one ($b)")
        #p < 0.5 || warn("Incoherent parameter: set is more likely ($(p)) to be in enabled state")
        new(a, b, reg,  min_weight)
    end
end

"""
Linear component of a set score.
Doesn't take into account the overlap with the other selected sets.
"""
function independentsetscore(set::Number, masked::Number, total::Number, total_masked::Number, params::CoverParams)
    #= P-value for masked-vs-set overlap enriched =# res = logpvalue(set, total_masked, total, masked) -
    #= P-value for unmasked-vs-set overlap enriched =# logpvalue(set, total - total_masked, total, set - masked)
    @assert !isnan(res) "set=$set masked=$masked total=$total total_masked=$total_masked res NaN"
    return res
end

"""
Optimal Enriched-Set Cover problem -- choose the sets from the collection to cover
the masked(selected) elements.
The optimal sets cover `C` needs to deliver to goals:
* minimize the P-values of masked elements enrichment for each of `C` sets
* minimize the P-values of the pairwise non-overlap of `C` sets with each other.

Fuzzy set selection is possible -- each set is assigned a weight from `[0, 1]` range.
"""
immutable CoverProblem
    params::CoverParams

    setXset_scores::Matrix{Float64}
    set_scores::Vector{Float64}

    function CoverProblem(mosaic::MaskedSetMosaic, params::CoverParams)
        # preprocess setXset scores matrix for numerical solution
        setXset_scores = mosaic.original.setXset_scores[mosaic.setixs, mosaic.setixs]
        min_score = 0.0
        @inbounds for i in eachindex(setXset_scores)
            if !isfinite(setXset_scores[i])
                s1, s2 = ind2sub(size(setXset_scores), i)
                warn("set[$s1]×set[$s2] score is $(setXset_scores[i])")
            elseif setXset_scores[i] < min_score
                min_score = setXset_scores[i]
            end
        end
        @inbounds for i in eachindex(setXset_scores)
            if isinf(setXset_scores[i]) && setXset_scores[i] < 0.0
                setXset_scores[i] = min_score
            end
        end
        @inbounds for i in 1:size(setXset_scores, 1)
            setXset_scores[i, i] = -params.reg
        end
        new(params, setXset_scores,
            Float64[independentsetscore(mosaic.original.set_sizes[mosaic.setixs[i]],
                        nmasked_perset(mosaic)[i],
                        nelements(mosaic), nmasked(mosaic), params) for i in 1:nsets(mosaic)])
    end
end

"""
Total number of sets in the collection.
"""
nsets(problem::CoverProblem) = length(problem.set_scores)

"""
Construct JuMP quadratic minimization model with linear contraints for the given OESC problem.
"""
function opt_model(problem::CoverProblem)
    m = JuMP.Model()
    ns = nsets(problem)
    @variable(m, 0.0 <= w[1:ns] <= 1.0)
    @objective(m, :Min, dot(problem.set_scores, w) - dot(w, problem.setXset_scores * w))
    return m
end

function fix_uncov_probs!(uncov_probs::Vector{Float64})
    pen = 0.0
    @inbounds for i in eachindex(uncov_probs)
        prob = uncov_probs[i]
        prob_new = clamp(prob, 0.0, 1.0)
        pen += abs2(prob_new - prob)
        uncov_probs[i] = prob_new
    end
    return pen
end

"""
Score (probability) of the OESC coverage.

* `w` probabilities of the sets being covered
"""
function score(problem::CoverProblem, w::Vector{Float64})
    # FIXME throw an error?
    #pen = fix_uncov_probs!(uncov_probs)
    dot(problem.set_scores - problem.setXset_scores * w, w)
end

"""
Result of `optimize(CoverProblem)`.
"""
immutable CoverProblemResult
    weights::Vector{Float64}
    score::Float64

    CoverProblemResult(weights::Vector{Float64}, score::Float64) =
        new(weights, score)
end

"""
Optimize the cover problem.
"""
function optimize(problem::CoverProblem;
                  ini_weights::Vector{Float64} = rand(nsets(problem)),
                  #iterations::Int = 100,
                  solver::MathProgBase.SolverInterface.AbstractMathProgSolver = IpoptSolver(print_level=0))
    (nsets(problem) == 0) && return CoverProblemResult(Float64[], 0.0)

    # Perform the optimization
    #try
    # using JuMP
    m = opt_model(problem)
    setsolver(m, solver)
    solve(m)
    w = copy(getvalue(getvariable(m, :w)))
    # remove small non-zero probabilities due to optimization method errors
    for i in eachindex(w)
        @inbounds if w[i] < problem.params.min_weight
            w[i] = 0.0
        end
    end
    return CoverProblemResult(w, getobjectivevalue(m))
    #catch x
    #    warn("Exception in optimize(CoverProblem): $x")
    #    return nothing
    #end
end
