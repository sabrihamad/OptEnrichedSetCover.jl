"""
Log P-value for the A and B sets intersection.
"""
function logpvalue(a_size::Integer, b_size::Integer,
                   all_size::Integer, isect_size::Integer,
                   tail::Symbol = :left)
    ((a_size >= 0) && (b_size >= 0) && (all_size >= 0)) || throw(ArgumentError("Sets with negative number of elements"))
    ((a_size <= all_size) && (b_size <= all_size)) || throw(ArgumentError("Sets bigger that total number of elements"))
    # corner cases
    if isect_size >= min(a_size, b_size)
        return tail == :right ? -Inf : 0.0
    elseif isect_size < min(0, a_size + b_size - all_size)
        return tail == :left ? -Inf : 0.0
    end
    # normal cases
    distr = Distributions.Hypergeometric(a_size, all_size - a_size, b_size)
    if tail == :left
        return logccdf(distr, isect_size-1)
    elseif tail == :right
        return logcdf(distr, isect_size)
    elseif tail == :both
        return 2.0 * min(logcdf(distr, isect_size),
                         logccdf(distr, isect_size-1), 0.5)
    else
        throw(ArgumentError("Unsupported tail specifier ($tail)"))
    end
end