################################################################################
#                   CORE DISPATCHVARIABLEREF METHOD EXTENSIONS
################################################################################
# Extend dispatch_variable_ref
function dispatch_variable_ref(model::InfiniteModel,
                               index::MeasureIndex)::MeasureRef
    return MeasureRef(model, index)
end

# Extend _add_data_object
function _add_data_object(model::InfiniteModel,
                          object::MeasureData)::MeasureIndex
    return MOIUC.add_item(model.measures, object)
end

# Extend _data_dictionary (type based)
function _data_dictionary(model::InfiniteModel, ::Type{Measure}
    )::MOIUC.CleverDict{MeasureIndex, MeasureData}
    return model.measures
end

# Extend _data_dictionary (reference based)
function _data_dictionary(mref::MeasureRef
    )::MOIUC.CleverDict{MeasureIndex, MeasureData}
    return JuMP.owner_model(mref).measures
end

# Extend _data_object
function _data_object(mref::MeasureRef)::MeasureData
  object = get(_data_dictionary(mref), JuMP.index(mref), nothing)
  object === nothing && error("Invalid measure reference, cannot find " *
                        "corresponding measure in the model. This is likely " *
                        "caused by using the reference of a deleted measure.")
  return object
end

# Extend _core_variable_object
function _core_variable_object(mref::MeasureRef)::Measure
    return _data_object(mref).measure
end

# Extend _object_numbers
function _object_numbers(mref::MeasureRef)::Vector{Int}
    return _core_variable_object(mref).object_nums
end

# Extend _parameter_numbers
function _parameter_numbers(mref::MeasureRef)::Vector{Int}
    return _core_variable_object(mref).parameter_nums
end

# Extend _set_core_variable_object
function _set_core_variable_object(mref::MeasureRef, object::Measure)::Nothing
    _data_object(mref).measure = object
    return
end

# Extend _measure_dependencies
function _measure_dependencies(mref::MeasureRef)::Vector{MeasureIndex}
    return _data_object(mref).measure_indices
end

# Extend _constraint_dependencies
function _constraint_dependencies(mref::MeasureRef)::Vector{ConstraintIndex}
    return _data_object(mref).constraint_indices
end

# Extend _derivative_dependencies
function _derivative_dependencies(mref::MeasureRef)::Vector{DerivativeIndex}
    return _data_object(mref).derivative_indices
end

################################################################################
#                              MEASURE DATA METHODS
################################################################################
# Extend Base.copy for DiscreteMeasureData
function Base.copy(data::DiscreteMeasureData)::DiscreteMeasureData
    return DiscreteMeasureData(copy(data.parameter_refs), copy(data.coefficients),
                               copy(data.supports), data.label,
                               data.weight_function, copy(data.lower_bounds),
                               copy(data.upper_bounds), data.is_expect)
end

# Extend Base.copy for FunctionalDiscreteMeasureData
function Base.copy(data::FunctionalDiscreteMeasureData)::FunctionalDiscreteMeasureData
    return FunctionalDiscreteMeasureData(copy(data.parameter_refs),
                                         data.coeff_function, data.min_num_supports,
                                         data.label, data.weight_function,
                                         copy(data.lower_bounds),
                                         copy(data.upper_bounds), data.is_expect)
end

"""
    default_weight(t) = 1

Default weight function for [`DiscreteMeasureData`](@ref) and
[`FunctionalDiscreteMeasureData`](@ref). Returns 1 regardless of the input value.
"""
default_weight(t) = 1

# Ensure that a pref is valid for use in measure data
function _check_params(pref::GeneralVariableRef)::Nothing
    if !(_index_type(pref) <: InfiniteParameterIndex)
        error("$pref is not an infinite parameter.")
    end
    return
end

"""
    DiscreteMeasureData(pref::GeneralVariableRef,
                        coefficients::Vector{<:Real},
                        supports::Vector{<:Real};
                        [label::Type{<:AbstractSupportLabel} = generate_unique_label(),
                        weight_function::Function = [`default_weight`](@ref),
                        lower_bound::Real = NaN,
                        upper_bound::Real = NaN,
                        is_expect::Bool = false]
                        )::DiscreteMeasureData

Returns a 1-dimensional `DiscreteMeasureData` object that can be utilized
to define measures using [`measure`](@ref). This accepts input for a scalar (single)
infinite parameter. A description of the other arguments is provided in the
documentation for [`DiscreteMeasureData`](@ref). Errors if supports are out
bounds or an unequal number of supports and coefficients are given. Note that by
default a unique `label` is generated via `generate_unique_label` to ensure the supports can
be located in the infinite parameter support storage. Advanced implementations,
may choose a different behavior but should do so with caution.

**Example**
```julia-repl
julia> data = DiscreteMeasureData(pref, [0.5, 0.5], [1, 2])
DiscreteMeasureData{GeneralVariableRef,1,Float64}(pref, [0.5, 0.5], [1.0, 2.0], Val{Symbol("##373")}, default_weight, NaN, NaN, false)
```
"""
function DiscreteMeasureData(pref::GeneralVariableRef,
    coefficients::Vector{<:Real},
    supports::Vector{<:Real};
    label::Type{<:AbstractSupportLabel} = generate_unique_label(),
    weight_function::Function = default_weight,
    lower_bound::Real = NaN,
    upper_bound::Real = NaN,
    is_expect::Bool = false
    )::DiscreteMeasureData{GeneralVariableRef, 1, Float64}
    _check_params(pref)
    if length(coefficients) != length(supports)
        error("The amount of coefficients must match the amount of " *
              "support points.")
    end
    set = infinite_set(pref)
    if !supports_in_set(supports, set)
        error("Support points violate parameter domain.")
    end
    return DiscreteMeasureData(pref, coefficients, supports, label,
                               weight_function, lower_bound, upper_bound,
                               is_expect)
end

# Ensure that an array of prefs is valid for use in multi-dimensional data
function _check_params(prefs::AbstractArray{GeneralVariableRef})::Nothing
    only_dep = all(_index_type(pref) == DependentParameterIndex for pref in prefs)
    only_indep = !only_dep && all(_index_type(pref) == IndependentParameterIndex
                                  for pref in prefs)
    if !only_dep && !only_indep
        error("Cannot specify a mixture of infinite parameter types.")
    elseif only_dep && any(_raw_index(pref) != _raw_index(first(prefs)) for pref in prefs)
        error("Cannot specify multiple dependent parameter groups for one measure.")
    elseif only_dep && length(prefs) != _num_parameters(first(dispatch_variable_ref.(prefs)))
        error("Cannot specify a subset of dependent parameters, consider using " *
              "nested one-dimensional measures instead.")
    end
    return
end

## Define function to intelligently format prefs and supports properly
# Vector
function _convert_param_refs_and_supports(
    prefs::Vector{GeneralVariableRef},
    supports::Vector{Vector{T}}
    )::Tuple{Vector{GeneralVariableRef}, Matrix{T}} where {T <: Real}
    return prefs, reduce(hcat, supports)
end

# DenseAxisArray and Arrays
function _convert_param_refs_and_supports(
    prefs::Union{Array{GeneralVariableRef},
                 JuMPC.DenseAxisArray{GeneralVariableRef}},
#    supports::Vector{<:JuMPC.DenseAxisArray{T}}
    supports::Union{Array{<:Array{T}},Vector{<:JuMPC.DenseAxisArray{T}}}
    )::Tuple{Vector{GeneralVariableRef}, Matrix{T}} where {T <: Real}
    return reduce(vcat, prefs), [supp[i] for i in eachindex(first(supports)), supp in supports]
end

# SparseAxisArray
function _convert_param_refs_and_supports(
    prefs::JuMPC.SparseAxisArray{GeneralVariableRef},
    supports::Vector{<:JuMPC.SparseAxisArray{T}}
    )::Tuple{Vector{GeneralVariableRef}, Matrix{T}} where {T <: Real}
    indices = Collections._get_indices(prefs)
    ordered_prefs = Collections._make_ordered(prefs, indices)
    supps = [Collections._make_ordered(supp, indices) for supp in supports]
    return _convert_param_refs_and_supports(ordered_prefs, supps)
end

## Check if a matrix of supports repsect infinite set(s)
# IndependentParameterRefs
function _check_supports_in_bounds(prefs::Vector{IndependentParameterRef},
                                   supports::Matrix{<:Real})::Nothing
    for i in eachindex(prefs)
        set = infinite_set(prefs[i])
        if !supports_in_set(supports[i, :], set)
            error("Support points violate parameter domain.")
        end
    end
    return
end

# DependentParameterRefs
function _check_supports_in_bounds(prefs::Vector{DependentParameterRef},
                                   supports::Matrix{<:Real})::Nothing
    set = _parameter_set(first(prefs))
    if !supports_in_set(supports, set)
        error("Support points violate parameter domain.")
    end
    return
end

"""
    DiscreteMeasureData(prefs::AbstractArray{GeneralVariableRef},
                        coefficients::Vector{<:Real},
                        supports::Vector{<:AbstractArray{<:Real}};
                        label::Type{<:AbstractSupportLabel} = generate_unique_label(),
                        weight_function::Function = [`default_weight`](@ref),
                        lower_bounds::AbstractArray{<:Real} = [NaN...],
                        upper_bounds::AbstractArray{<:Real} = [NaN...],
                        is_expect::Bool = false
                        )::DiscreteMeasureData

Returns a `DiscreteMeasureData` object that can be utilized to
define measures using [`measure`](@ref). This accepts input for an array (multi)
parameter. The inner arrays in the supports vector need to match the formatting
of the array used for `parameter_refs`. A description of the other arguments is
provided in the
documentation for [`DiscreteMeasureData`](@ref). Errors if supports are out
bounds, an unequal number of supports and coefficients are given, the array
formats do not match, or if mixed infinite parameter types are given. Note that by
default a unique `label` is generated via `generate_unique_label` to ensure the supports can
be located in the infinite parameter support storage. Advanced implementations,
may choose a different behavior but should do so with caution.

**Example**
```julia-repl
julia> data = DiscreteMeasureData(prefs, [0.5, 0.5], [[1, 1], [2, 2]]);

julia> typeof(data)
DiscreteMeasureData{Array{GeneralVariableRef,1},2,Array{Float64,1}}
```
"""
function DiscreteMeasureData(prefs::AbstractArray{GeneralVariableRef},
    coefficients::Vector{<:Real},
    supports::Vector{<:AbstractArray{<:Real}};
    label::Type{<:AbstractSupportLabel} = generate_unique_label(),
    weight_function::Function = default_weight,
    lower_bounds::AbstractArray{<:Real} = map(e -> NaN, prefs),
    upper_bounds::AbstractArray{<:Real} = map(e -> NaN, prefs),
    is_expect::Bool = false
    )::DiscreteMeasureData{Vector{GeneralVariableRef}, 2, Vector{Float64}}
    _check_params(prefs) # ensures that prefs are valid
    if _keys(prefs) != _keys(first(supports))
        error("Parameter references and supports must use same container type.")
    elseif _keys(prefs) != _keys(lower_bounds)
        error("Parameter references and bounds must use same container type.")
    end
    if length(coefficients) != length(supports)
        error("The amount of coefficients must match the amount of " *
              "support points.")
    end
    vector_prefs, supps = _convert_param_refs_and_supports(prefs, supports)
    _check_supports_in_bounds(dispatch_variable_ref.(vector_prefs), supps)
    lb = _make_ordered_vector(lower_bounds)
    ub = _make_ordered_vector(upper_bounds)
    return DiscreteMeasureData(vector_prefs, coefficients, supps, label,
                               weight_function, lb, ub, is_expect)
end

"""
    FunctionalDiscreteMeasureData(pref::GeneralVariableRef,
                                  coeff_func::Function,
                                  min_num_supports::Int,
                                  label::Type{<:AbstractSupportLabel};
                                  [weight_function::Function = [`default_weight`](@ref),
                                  lower_bound::Real = NaN,
                                  upper_bound::Real = NaN,
                                  is_expect::Bool = false]
                                  )::FunctionalDiscreteMeasureData

Returns a 1-dimensional `FunctionalDiscreteMeasureData` object that can be utilized
to define measures using [`measure`](@ref). This accepts input for a scalar (single)
infinite parameter. A description of the other arguments is provided in the
documentation for [`FunctionalDiscreteMeasureData`](@ref). Errors if `pref` is
not an infinite parameter. Built-in choices for `label` include:
- `All`: Use all of the supports stored in `pref`
- `MCSample`: Use Monte Carlo samples associated with `pref`
- `WeightedSample`: Use weighted Monte Carlo samples associated with `pref`
- `UniformGrid`: Use uniform grid points associated with `pref`.

**Example**
```julia-repl
julia> data = FunctionalDiscreteMeasureData(pref, my_func, 20, UniformGrid)
FunctionalDiscreteMeasureData{GeneralVariableRef,Float64}(pref, my_func, 20, UniformGrid, default_weight, NaN, NaN, false)
```
"""
function FunctionalDiscreteMeasureData(
    pref::GeneralVariableRef,
    coeff_func::Function,
    min_num_supports::Int,
    label::Type{<:AbstractSupportLabel};
    weight_function::Function = default_weight,
    lower_bound::Real = NaN,
    upper_bound::Real = NaN,
    is_expect::Bool = false
    )::FunctionalDiscreteMeasureData{GeneralVariableRef,Float64}
    _check_params(pref)
    if _index_type(pref) == DependentParameterIndex && min_num_supports != 0
        error("`min_num_supports` must be 0 for individual dependent parameters.")
    end
    min_num_supports >= 0 || error("Number of supports must be nonnegative.")
    if !isnan(lower_bound) && !isnan(upper_bound)
        if !supports_in_set([lower_bound, upper_bound], infinite_set(pref))
            error("Bounds violate infinite set bounds.")
        end
    end
    return FunctionalDiscreteMeasureData(pref, coeff_func, min_num_supports,
                                         label, weight_function,
                                         lower_bound, upper_bound, is_expect)
end

## Check if the integral bounds satisfy the parameter set(s)
# IndependentParameterRefs
function _check_bounds_in_set(prefs::Vector{IndependentParameterRef}, lbs,
                              ubs)::Nothing
    for i in eachindex(prefs)
        if !supports_in_set([lbs[i], ubs[i]], infinite_set(prefs[i]))
            error("Bounds violate the infinite domain.")
        end
    end
    return
end

# DependentParameterRefs
function _check_bounds_in_set(prefs::Vector{DependentParameterRef}, lbs,
                              ubs)::Nothing
    if !supports_in_set(hcat(lbs, ubs), infinite_set(prefs))
        error("Bounds violate the infinite domain.")
    end
    return
end

"""
    FunctionalDiscreteMeasureData(prefs::AbstractArray{GeneralVariableRef},
                                  coeff_func::Function,
                                  min_num_supports::Int,
                                  label::Type{<:AbstractSupportLabel};
                                  [weight_function::Function = [`default_weight`](@ref),
                                  lower_bounds::AbstractArray{<:Real} = [NaN...],
                                  upper_bounds::AbstractArray{<:Real} = [NaN...],
                                  is_expect::Bool = false]
                                  )::FunctionalDiscreteMeasureData

Returns a multi-dimensional `FunctionalDiscreteMeasureData` object that can be utilized
to define measures using [`measure`](@ref). This accepts input for an array of
infinite parameters. A description of the other arguments is provided in the
documentation for [`FunctionalDiscreteMeasureData`](@ref). Errors if `prefs` are
not infinite parameters or if the mixed parameter types are provided.
Built-in choices for `label` include:
- `All`: Use all of the supports stored in `prefs`
- `MCSample`: Use Monte Carlo samples associated with `prefs`
- `WeightedSample`: Use weighted Monte Carlo samples associated with `prefs`
- `UniformGrid`: Use uniform grid points associated with `prefs`.

**Example**
```julia-repl
julia> data = FunctionalDiscreteMeasureData(prefs, my_func, 20, MCSample);
```
"""
function FunctionalDiscreteMeasureData(
    prefs::AbstractArray{GeneralVariableRef},
    coeff_func::Function,
    min_num_supports::Int,
    label::Type{<:AbstractSupportLabel};
    weight_function::Function = default_weight,
    lower_bounds::AbstractArray{<:Real} = map(e -> NaN, prefs),
    upper_bounds::AbstractArray{<:Real} = map(e -> NaN, prefs),
    is_expect::Bool = false
    )::FunctionalDiscreteMeasureData{Vector{GeneralVariableRef},Vector{Float64}}
    _check_params(prefs)
    if _keys(prefs) != _keys(lower_bounds)
        error("Parameter references and bounds must use same container type.")
    end
    min_num_supports >= 0 || error("Number of supports must be nonnegative.")
    vector_prefs = _make_ordered_vector(prefs)
    vector_lbs = _make_ordered_vector(lower_bounds)
    vector_ubs = _make_ordered_vector(upper_bounds)
    if !isnan(first(vector_lbs)) && !isnan(first(vector_ubs))
        dprefs = map(p -> dispatch_variable_ref(p), vector_prefs)
        _check_bounds_in_set(dprefs, vector_lbs, vector_ubs)
    end
    return FunctionalDiscreteMeasureData(vector_prefs, coeff_func, min_num_supports,
                                         label, weight_function, lower_bounds,
                                         upper_bounds, is_expect)
end

"""
    parameter_refs(data::AbstractMeasureData)::Union{GeneralVariableRef,
                                                     AbstractArray{GeneralVariableRef}}

Return the infinite parameter reference(s) in `data`. This is intended as an
internal function to be used with measure addition. User-defined measure data types
will need to extend this function otherwise an error is thrown.
"""
function parameter_refs(data::AbstractMeasureData)
    error("Function `parameter_refs` not extended for measure data of type $(typeof(data)).")
end

# DiscreteMeasureData
function parameter_refs(data::DiscreteMeasureData{T})::T where {T}
    return data.parameter_refs
end

# FunctionalDiscreteMeasureData
function parameter_refs(data::FunctionalDiscreteMeasureData{T})::T where {T}
    return data.parameter_refs
end

"""
    support_label(data::AbstractMeasureData)::Type{<:AbstractSupportLabel}

Return the label stored in `data` associated with its supports.
This is intended as en internal method for measure creation and ensures any
new supports are added to parameters with such a label.
User-defined measure data types should extend this functionif supports are used,
otherwise an error is thrown.
"""
function support_label(data::AbstractMeasureData)
    error("Function `support_label` not defined for measure data of type " *
          "$(typeof(data)).")
end

# DiscreteMeasureData and FunctionalDiscreteMeasureData
function support_label(data::Union{FunctionalDiscreteMeasureData,
                       DiscreteMeasureData})::Type{<:AbstractSupportLabel}
    return data.label
end

"""
    JuMP.lower_bound(data::AbstractMeasureData)::Union{Float64, Vector{Float64}}

Return the lower bound associated with `data` that defines its domain. This is
intended as an internal method, but may be useful for extensions. User-defined
measure data types should extend this function if desired, otherwise `NaN` is
returned
"""
function JuMP.lower_bound(data::AbstractMeasureData)::Float64
    return NaN
end

# DiscreteMeasureData and FunctionalDiscreteMeasureData
function JuMP.lower_bound(data::Union{FunctionalDiscreteMeasureData,
                                      DiscreteMeasureData})
    return data.lower_bounds
end

"""
    JuMP.upper_bound(data::AbstractMeasureData)::Union{Float64, Vector{Float64}}

Return the lower bound associated with `data` that defines its domain. This is
intended as an internal method, but may be useful for extensions. User-defined
measure data types should extend this function if desired, otherwise `NaN` is
returned.
"""
function JuMP.upper_bound(data::AbstractMeasureData)::Float64
    return NaN
end

# DiscreteMeasureData and FunctionalDiscreteMeasureData
function JuMP.upper_bound(data::Union{FunctionalDiscreteMeasureData,
                                      DiscreteMeasureData})
    return data.upper_bounds
end

## Indicate is the data is from an expectation call
# Fallback
function _is_expect(data::AbstractMeasureData)::Bool
    return false
end

# DiscreteMeasureData and FunctionalDiscreteMeasureData
function _is_expect(data::Union{FunctionalDiscreteMeasureData,
                                DiscreteMeasureData})::Bool
    return data.is_expect
end

"""
    supports(data::AbstractMeasureData)::Array{Float64}

Return the supports associated with `data` and its infinite parameters.
This is intended as en internal method for measure creation and ensures any
new supports are added to parameters. User-defined measure data types should
extend this function if appropriate, otherwise an empty vector is returned.
"""
function supports(data::AbstractMeasureData)::Vector{Float64}
    return Float64[]
end

# DiscreteMeasureData
function supports(data::DiscreteMeasureData{T, N})::Array{Float64, N} where {T, N}
    return data.supports
end

# 1D FunctionalDiscreteMeasureData
function supports(data::FunctionalDiscreteMeasureData{GeneralVariableRef})::Vector{Float64}
    supps = supports(parameter_refs(data), label = support_label(data))
    lb = JuMP.lower_bound(data)
    ub = JuMP.upper_bound(data)
    if isnan(lb) && isnan(ub)
        return supps
    else
        return filter!(i -> lb <= i <= ub, supps)
    end
end

# Multi FunctionalDiscreteMeasureData
function supports(data::FunctionalDiscreteMeasureData{Vector{GeneralVariableRef}})::Matrix{Float64}
    supps = supports(parameter_refs(data), label = support_label(data))
    lb = JuMP.lower_bound(data)
    ub = JuMP.upper_bound(data)
    if isnan(first(lb)) && isnan(first(ub))
        return supps
    else
        inds = [all(lb .<= @view(supps[:, i]) .<= ub) for i in 1:size(supps, 2)]
        return supps[:, inds]
    end
end

"""
    num_supports(data::AbstractMeasureData)::Int

Return the number supports associated with `data` and its infinite parameters.
This is intended as an internal method for measure creation. User-defined
measure data types should extend this function if appropriate, otherwise
0 is returned.
"""
function num_supports(data::AbstractMeasureData)::Int
    return 0
end

# DiscreteMeasureData/FunctionalDiscreteMeasureData
function num_supports(data::Union{FunctionalDiscreteMeasureData,
                                  DiscreteMeasureData})::Int
    return size(supports(data))[end]
end

"""
    min_num_supports(data::AbstractMeasureData)::Int

Return the minimum number of supports associated with `data`. By fallback, this
will just return `num_supports(data)`. This is primarily intended for internal
queries of `FunctionalDiscreteMeasureData`, but can be extended for other
measure data types if needed.
"""
function min_num_supports(data::AbstractMeasureData)::Int
    return num_supports(data)
end

# FunctionalDiscreteMeasureData
function min_num_supports(data::FunctionalDiscreteMeasureData)::Int
    return data.min_num_supports
end

"""
    coefficient_function(data::AbstractMeasureData)::Function

Return the coefficient function stored in `data` associated with its
expansion abstraction is there is such a function. This is intended as an
internal method for measure creation. User-defined measure
data types should extend this function if appropriate, otherwise an error is
thrown for unsupported types.
"""
function coefficient_function(data::AbstractMeasureData)::Function
    error("Function `coefficient_function` not defined for measure data of type " *
          "$(typeof(data)).")
end

# FunctionalDiscreteMeasureData
function coefficient_function(data::FunctionalDiscreteMeasureData)::Function
    return data.coeff_function
end

"""
    coefficients(data::AbstractMeasureData)::Vector{<:Real}

Return the coefficients associated with `data` associated with its expansion abstraction.
This is intended as en internal method for measure creation. User-defined measure
data types should extend this function if appropriate, otherwise an empty vector
is returned.
"""
function coefficients(data::AbstractMeasureData)::Vector{Float64}
    return Float64[]
end

# DiscreteMeasureData
function coefficients(data::DiscreteMeasureData)::Vector{Float64}
    return data.coefficients
end

# FunctionalDiscreteMeasureData
function coefficients(data::FunctionalDiscreteMeasureData)::Vector{Float64}
    return data.coeff_function(supports(data))
end

"""
    weight_function(data::AbstractMeasureData)::Function

Return the weight function stored in `data` associated with its expansion abstraction.
This is intended as en internal method for measure creation. User-defined measure
data types should extend this function if appropriate, otherwise an error is thrown.
"""
function weight_function(data::AbstractMeasureData)::Function
    error("Function `weight_function` not defined for measure data of type " *
          "$(typeof(data)).")
end

# DiscreteMeasureData and FunctionalDiscreteMeasureData
function weight_function(data::Union{DiscreteMeasureData,
                                     FunctionalDiscreteMeasureData})::Function
    return data.weight_function
end

################################################################################
#                            MEASURE CONSTRUCTION METHODS
################################################################################
"""
    measure_data_in_hold_bounds(data::AbstractMeasureData,
                                bounds::ParameterBounds)::Bool

Return a `Bool` whether the domain of `data` is valid in accordance with
`bounds`. This is intended as an internal method and is used to check hold
variables used in measures. User-defined measure data types will need to
extend this function to enable this error checking, otherwise it is skipped and
a warning is given.
"""
function measure_data_in_hold_bounds(data::AbstractMeasureData,
                                     bounds::ParameterBounds)::Bool
    @warn "Unable to check if hold variables bounds are valid in measure " *
           "with measure data type `$(typeof(data))`. This can be resolved by " *
           "extending `measure_data_in_hold_bounds`."
    return true
end

# Scalar DiscreteMeasureData and FunctionalDiscreteMeasureData
function measure_data_in_hold_bounds(
    data::Union{DiscreteMeasureData{P, 1}, FunctionalDiscreteMeasureData{P}},
    bounds::ParameterBounds{GeneralVariableRef}
    )::Bool where {P <: GeneralVariableRef}
    pref = parameter_refs(data)
    supps = supports(data)
    if haskey(bounds, pref) && length(supps) != 0
        return supports_in_set(supps, bounds[pref])
    end
    return true
end

# Multi-dimensional DiscreteMeasureData and FunctionalDiscreteMeasureData
function measure_data_in_hold_bounds(
    data::Union{DiscreteMeasureData{P, 2}, FunctionalDiscreteMeasureData{P}},
    bounds::ParameterBounds{GeneralVariableRef}
    )::Bool where {P <: Vector{GeneralVariableRef}}
    prefs = parameter_refs(data)
    supps = supports(data)
    if length(supps) != 0
        for i in eachindex(prefs)
            if haskey(bounds, prefs[i])
                if !supports_in_set(supps[i, :], bounds[prefs[i]])
                    return false
                end
            end
        end
    end
    return true
end

# Check that variables don't violate the parameter bounds
function _check_var_bounds(vref::GeneralVariableRef, data::AbstractMeasureData)
    if _index_type(vref) == HoldVariableIndex
        bounds = parameter_bounds(vref)
        if !measure_data_in_hold_bounds(data, bounds)
            error("Measure bounds violate hold variable bounds.")
        end
    elseif _index_type(vref) == MeasureIndex
        vrefs = _all_function_variables(measure_function(vref))
        for vref in vrefs
            _check_var_bounds(vref, data)
        end
    end
    return
end

"""
    build_measure(expr::JuMP.AbstractJuMPScalar,
                  data::AbstractMeasureData)::Measure

Build and return a [`Measure`](@ref) given the expression to be measured `expr`
using measure data `data`. This principally serves as an internal method for
measure definition. Errors if the supports associated with `data` violate
an hold variable parameter bounds of hold variables that are included in the
measure.
"""
function build_measure(expr::T, data::D;
    )::Measure{T, D} where {T <: JuMP.AbstractJuMPScalar, D <: AbstractMeasureData}
    vrefs = _all_function_variables(expr)
    model = _model_from_expr(vrefs)
    if model.has_hold_bounds
        for vref in vrefs
            _check_var_bounds(vref, data)
        end
    end
    expr_obj_nums = _object_numbers(expr)
    expr_param_nums = _parameter_numbers(expr)
    prefs = parameter_refs(data)
    data_obj_nums = _object_numbers(prefs)
    data_param_nums = [_parameter_number(pref) for pref in prefs]
    # NOTE setdiff! cannot be used here since it modifies object_nums of expr if expr is a single infinite variable
    obj_nums = sort(setdiff(expr_obj_nums, data_obj_nums))
    param_nums = sort(setdiff(expr_param_nums, data_param_nums))
    # check if analytic method should be applied
    lb_nan = isnan(first(JuMP.lower_bound(data)))
    ub_nan = isnan(first(JuMP.upper_bound(data)))
    # NOTE intersect! cannot be used here since it modifies parameter_nums of expr if expr is a single infinite variable
    constant_func = isempty(intersect(expr_param_nums, data_param_nums)) &&
                    ((!lb_nan && !ub_nan) || _is_expect(data))
    return Measure(expr, data, obj_nums, param_nums, constant_func)
end

################################################################################
#                               DEFINITION METHODS
################################################################################
function _add_supports_to_multiple_parameters(
    prefs::Vector{DependentParameterRef},
    supps::Array{Float64, 2},
    label::Type{<:AbstractSupportLabel}
    )::Nothing
    add_supports(prefs, supps, label = label, check = false)
    return
end

function _add_supports_to_multiple_parameters(
    prefs::Vector{IndependentParameterRef},
    supps::Array{Float64, 2},
    label::Type{<:AbstractSupportLabel}
    )::Nothing
    for i in eachindex(prefs)
        add_supports(prefs[i], supps[i, :], label = label, check = false)
    end
    return
end

"""
    add_supports_to_parameters(data::AbstractMeasureData)::Nothing

Add supports as appropriate with `data` to the underlying infinite parameters.
This is an internal method with by [`add_measure`](@ref) and should be defined
for user-defined measure data types.
"""
function add_supports_to_parameters(data::AbstractMeasureData)
    error("`add_supports_to_parameters` not defined for measures with " *
          "measure data type $(typeof(data)).")
end

## Internal functions for adding measure data supports to the parameter supports
# scalar DiscreteMeasureData
function add_supports_to_parameters(
    data::DiscreteMeasureData{GeneralVariableRef, 1}
    )::Nothing
    pref = parameter_refs(data)
    supps = supports(data)
    label = support_label(data)
    add_supports(pref, supps, label = label, check = false)
    return
end

# multi-dimensional DiscreteMeasureData
function add_supports_to_parameters(
    data::DiscreteMeasureData{Vector{GeneralVariableRef}, 2}
    )::Nothing
    prefs = map(p -> dispatch_variable_ref(p), parameter_refs(data))
    supps = supports(data)
    label = support_label(data)
    _add_supports_to_multiple_parameters(prefs, supps, label)
    return
end

# scalar FunctionalDiscreteMeasureData
function add_supports_to_parameters(
    data::FunctionalDiscreteMeasureData{GeneralVariableRef}
    )::Nothing
    # determine if we need to add more supports
    num_supps = min_num_supports(data)
    curr_num_supps = num_supports(data)
    if curr_num_supps < num_supps
        # prepare the parameter reference
        pref = dispatch_variable_ref(parameter_refs(data))
        if pref isa DependentParameterRef # This is just a last line of defense
            error("min_num_supports must be 0 for individual dependent parameters.")
        end
        # prepare the generation set
        lb = JuMP.lower_bound(data)
        ub = JuMP.upper_bound(data)
        if isnan(lb) || isnan(ub)
            set = infinite_set(pref)
        else
            set = IntervalSet(lb, ub) # assumes lb and ub are in the set
        end
        # generate the needed supports
        label = support_label(data)
        generate_and_add_supports!(pref, set, label,
                                   num_supports = num_supps - curr_num_supps)
    end
    return
end

## generate more supports as needed in accordance with a label
# DependentParameterRefs
function _generate_multiple_functional_supports(
    prefs::Vector{DependentParameterRef},
    num_supps::Int, label::Type{<:AbstractSupportLabel},
    lower_bounds::Vector{<:Number},
    upper_bounds::Vector{<:Number}
    )::Nothing
    # prepare the generation set
    if isnan(first(lower_bounds)) || isnan(first(upper_bounds))
        set = infinite_set(prefs)
    else
        # assumes we have valid bounds
        set = CollectionSet([IntervalSet(lower_bounds[i], upper_bounds[i])
                             for i in eachindex(lower_bounds)])
    end
    # generate the supports
    generate_and_add_supports!(prefs, set, label, num_supports = num_supps)
    return
end

# IndependentParameterRefs
function _generate_multiple_functional_supports(
    prefs::Vector{IndependentParameterRef},
    num_supps::Int, label::Type{<:AbstractSupportLabel},
    lower_bounds::Vector{<:Number},
    upper_bounds::Vector{<:Number}
    )::Nothing
    # we are gauranteed that each have the same number of supports
    for i in eachindex(prefs)
        # prepare the generation set
        if isnan(lower_bounds[i]) || isnan(upper_bounds[i])
            set = infinite_set(prefs[i])
        else
            # assumes lb and ub are in the set
            set = IntervalSet(lower_bounds[i], upper_bounds[i])
        end
        # generate the supports
        generate_and_add_supports!(prefs[i], set, label, num_supports = num_supps)
    end
    return
end

# multi-dimensional FunationalDiscreteMeasureData
function add_supports_to_parameters(
    data::FunctionalDiscreteMeasureData{Vector{GeneralVariableRef}}
    )::Nothing
    min_num_supps = min_num_supports(data)
    curr_num_supps = num_supports(data) # this will error check the support dims
    needed_supps = min_num_supps - curr_num_supps
    if needed_supps > 0
        prefs = map(p -> dispatch_variable_ref(p), parameter_refs(data))
        label = support_label(data)
        lbs = JuMP.lower_bound(data)
        ubs = JuMP.upper_bound(data)
        _generate_multiple_functional_supports(prefs, needed_supps, label, lbs,
                                               ubs)
    end
    return
end

"""
    add_measure(model::InfiniteModel, meas::Measure,
                name::String = "measure")::GeneralVariableRef

Add a measure to `model` and return the corresponding measure reference. This
operates in a manner similar to `JuMP.add_variable`. Note this intended
as an internal method.
"""
function add_measure(model::InfiniteModel, meas::Measure,
                     name::String = "measure")::GeneralVariableRef
    # get the expression variables and check validity
    vrefs = _all_function_variables(meas.func)
    for vref in vrefs
        JuMP.check_belongs_to_model(vref, model)
    end
    # get the measure data info and check validity
    data = meas.data
    prefs = parameter_refs(data)
    for pref in prefs
        JuMP.check_belongs_to_model(pref, model)
    end
    # add supports to the model as needed
    if !meas.constant_func
        add_supports_to_parameters(data)
    end
    # add the measure to the model
    object = MeasureData(meas, name)
    mindex = _add_data_object(model, object)
    mref = _make_variable_ref(model, mindex)
    # update mappings
    for vref in union!(vrefs, prefs)
        push!(_measure_dependencies(vref), mindex)
    end
    return mref
end

"""
    measure_function(mref::MeasureRef)::JuMP.AbstractJuMPScalar

Return the function associated with `mref`.

**Example**
```julia-repl
julia> measure_function(meas)
y(x, t) + 2
```
"""
function measure_function(mref::MeasureRef)::JuMP.AbstractJuMPScalar
    return _core_variable_object(mref).func
end

"""
    measure_data(mref::MeasureRef)::AbstractMeasureData

Return the measure data associated with `mref`.

**Example**
```julia-repl
julia> data = measure_data(meas);

julia> typeof(data)
FunctionalDiscreteMeasureData{Vector{GeneralVariableRef},Vector{Float64}}
```
"""
function measure_data(mref::MeasureRef)::AbstractMeasureData
    return _core_variable_object(mref).data
end

"""
    is_analytic(mref::MeasureRef)::Bool

Return if `mref` is evaluated analytically.

**Example**
```julia-repl
julia> is_analytic(meas)
false
```
"""
function is_analytic(mref::MeasureRef)::Bool
    return _core_variable_object(mref).constant_func
end

## Return an element of a parameter reference tuple given the model, index, and parameter numbers
# IndependentParameterIndex
function _make_param_tuple_element(model::InfiniteModel,
    idx::IndependentParameterIndex,
    param_nums::Vector{Int}
    )::GeneralVariableRef
    return _make_parameter_ref(model, idx)
end

# DependentParametersIndex
function _make_param_tuple_element(model::InfiniteModel,
    idx::DependentParametersIndex,
    param_nums::Vector{Int}
    )::Union{GeneralVariableRef, Vector{GeneralVariableRef}}
    dpref = DependentParameterRef(model, DependentParameterIndex(idx, 1))
    el_param_nums = _data_object(dpref).parameter_nums
    prefs = [GeneralVariableRef(model, idx.value, DependentParameterIndex, i)
             for i in eachindex(el_param_nums) if el_param_nums[i] in param_nums]
    return length(prefs) > 1 ? prefs : first(prefs)
end

"""
    parameter_refs(mref::MeasureRef)::Tuple

Return the tuple of infinite parameters that the measured expression associated
`mref` depends on once the measure has been evaluated. Note that this will
correspond to the parameter dependencies of the measure function excluding those
included in the measure data.

**Example**
```julia-repl
julia> parameter_refs(meas)
(t,)
```
"""
function parameter_refs(mref::MeasureRef)::Tuple
    model = JuMP.owner_model(mref)
    obj_indices = _param_object_indices(model)[_object_numbers(mref)]
    param_nums = _parameter_numbers(mref)
    return Tuple(_make_param_tuple_element(model, idx, param_nums)
                 for idx in obj_indices)
end

# Extend raw_parameter_refs (this is helpful for defining derivatives)
function raw_parameter_refs(mref::MeasureRef)::VectorTuple{GeneralVariableRef}
    return VectorTuple(parameter_refs(mref))
end

# Extend parameter_list (this is helpful for defining derivatives)
function parameter_list(mref::MeasureRef)::Vector{GeneralVariableRef}
    return raw_parameter_refs(mref).values
end

"""
    measure(expr::JuMP.AbstractJuMPScalar,
            data::AbstractMeasureData;
            [name::String = "measure"])::GeneralVariableRef

Return a measure reference that evaluates `expr` using according to `data`.
The measure data `data` determines how the measure is to be evaluated.
Typically, the `DiscreteMeasureData` and the `FunctionalDiscreteMeasureData`
constructors can be used to for `data`. The variable expression `expr` can contain
`InfiniteOpt` variables, infinite parameters, other measure references (meaning
measures can be nested), and constants. Typically, this is called inside of
[`JuMP.@expression`](@ref), [`JuMP.@objective`](@ref), and
[`JuMP.@constraint`](@ref) in a manner similar to `sum`. Note measures are not
explicitly evaluated until [`build_optimizer_model!`](@ref) is called or unless
they are expanded via [`expand`](@ref) or [`expand_all_measures!`](@ref).

**Example**
```julia-repl
julia> tdata = DiscreteMeasureData(t, [0.5, 0.5], [1, 2]);

julia> xdata = DiscreteMeasureData(xs, [0.5, 0.5], [[-1, -1], [1, 1]]);

julia> constr_RHS = @expression(model, measure(g - s + 2, tdata) + s^2)
measure{t}[g(t) - s + 2] + s²

julia> @objective(model, Min, measure(g - 1  + measure(T, xdata), tdata))
measure{xs}[g(t) - 1 + measure{xs}[T(t, x)]]
```
"""
function measure(expr::JuMP.AbstractJuMPScalar,
                 data::AbstractMeasureData;
                 name::String = "measure")::GeneralVariableRef
    model = _model_from_expr(expr)
    if model === nothing
        error("Expression contains no variables or parameters.")
    end
    meas = build_measure(expr, data)
    return add_measure(model, meas, name)
end

"""
    @measure(expr::JuMP.AbstractJuMPScalar,
             data::AbstractMeasureData;
             [name::String = "measure"])::GeneralVariableRef

An efficient wrapper for [`measure`](@ref), please see its doc string for more
information.
"""
macro measure(expr, data, args...)
    _error(str...) = _macro_error(:measure, (expr, args...), str...)
    extra, kw_args, requestedcontainer = _extract_kw_args(args)
    if length(extra) != 0
        _error("Incorrect number of arguments. Must be of form " *
               "@measure(expr, data, name = ...).")
    end
    if !isempty(filter(kw -> kw.args[1] != :name, kw_args))
        _error("Invalid keyword arguments. Must be of form " *
               "@measure(expr, data, name = ...).")
    end
    expression = :( JuMP.@expression(InfiniteOpt._Model, $expr) )
    mref = :( measure($expression, $data; ($(kw_args...))) )
    return esc(mref)
end

################################################################################
#                               NAMING METHODS
################################################################################
"""
    JuMP.name(mref::MeasureRef)::String

Extend `JuMP.name` to return the name associated with a measure
reference.
"""
function JuMP.name(mref::MeasureRef)::String
    object = get(_data_dictionary(mref), JuMP.index(mref), nothing)
    return object === nothing ? "" : object.name
end

"""
    JuMP.set_name(mref::MeasureRef, name::String)::Nothing

Extend `JuMP.set_name` to specify the name of a measure reference.
"""
function JuMP.set_name(mref::MeasureRef, name::String)::Nothing
    _data_object(mref).name = name
    return
end

################################################################################
#                              DEPENDENCY METHODS
################################################################################
"""
    used_by_measure(mref::MeasureRef)::Bool

Return a `Bool` indicating if `mref` is used by a measure.

**Example**
```julia-repl
julia> used_by_measure(mref)
true
```
"""
function used_by_measure(mref::MeasureRef)::Bool
    return !isempty(_measure_dependencies(mref))
end

"""
    used_by_constraint(mref::MeasureRef)::Bool

Return a `Bool` indicating if `mref` is used by a constraint.

**Example**
```julia-repl
julia> used_by_constraint(mref)
false
```
"""
function used_by_constraint(mref::MeasureRef)::Bool
    return !isempty(_constraint_dependencies(mref))
end

"""
    used_by_objective(mref::MeasureRef)::Bool

Return a `Bool` indicating if `mref` is used by the objective.

**Example**
```julia-repl
julia> used_by_objective(mref)
true
```
"""
function used_by_objective(mref::MeasureRef)::Bool
    return _data_object(mref).in_objective
end

"""
    used_by_derivative(mref::MeasureRef)::Bool

Return a `Bool` indicating if `mref` is used by a derivative.

**Example**
```julia-repl
julia> used_by_derivative(mref)
true
```
"""
function used_by_derivative(mref::MeasureRef)::Bool
    return !isempty(_derivative_dependencies(mref))
end

"""
    is_used(mref::MeasureRef)::Bool

Return a `Bool` indicating if `mref` is used in the model.

**Example**
```julia-repl
julia> is_used(mref)
true
```
"""
function is_used(mref::MeasureRef)::Bool
    return used_by_measure(mref) || used_by_constraint(mref) ||
           used_by_objective(mref) || used_by_derivative(mref)
end

################################################################################
#                                GENERAL QUERIES
################################################################################
"""
    num_measures(model::InfiniteModel)::Int

Return the number of measures defined in `model`.

**Example**
```julia-repl
julia> num_measures(model)
2
```
"""
function num_measures(model::InfiniteModel)::Int
    return length(_data_dictionary(model, Measure))
end

"""
    all_measures(model::InfiniteModel)::Vector{GeneralVariableRef}

Return the list of all measures added to `model`.

**Examples**
```julia-repl
julia> all_measures(model)
2-element Array{GeneralVariableRef,1}:
 ∫{t ∈ [0, 6]}[w(t, x)]
 𝔼{x}[w(t, x)]
```
"""
function all_measures(model::InfiniteModel)::Vector{GeneralVariableRef}
    vrefs_list = Vector{GeneralVariableRef}(undef, num_measures(model))
    for (i, (index, _)) in enumerate(_data_dictionary(model, Measure))
        vrefs_list[i] = _make_variable_ref(model, index)
    end
    return vrefs_list
end

################################################################################
#                                   DELETION
################################################################################
"""
    JuMP.delete(model::InfiniteModel, mref::MeasureRef)::Nothing

Extend [`JuMP.delete`](@ref) to delete measures. Errors if measure is invalid,
meaning it does not belong to the model or it has already been deleted.

**Example**
```julia-repl
julia> print(model)
Min ∫{t ∈ [0, 6]}[g(t)] + z
Subject to
 z ≥ 0.0
 ∫{t ∈ [0, 6]}[g(t)] = 0
 g(t) + z ≥ 42.0, ∀ t ∈ [0, 6]
 g(0.5) = 0

julia> delete(model, meas)

julia> print(model)
Min z
Subject to
 z ≥ 0.0
 0 = 0
 g(t) + z ≥ 42.0, ∀ t ∈ [0, 6]
 g(0.5) = 0
```
"""
function JuMP.delete(model::InfiniteModel, mref::MeasureRef)::Nothing
    @assert JuMP.is_valid(model, mref) "Invalid measure reference."
    # Reset the transcription status
    if is_used(mref)
        set_optimizer_model_ready(model, false)
    end
    gvref = _make_variable_ref(JuMP.owner_model(mref), JuMP.index(mref))
    # Remove from dependent measures if there are any
    for mindex in _measure_dependencies(mref)
        meas_ref = dispatch_variable_ref(model, mindex)
        func = measure_function(meas_ref)
        data = measure_data(meas_ref)
        if func isa GeneralVariableRef
            new_func = zero(JuMP.GenericAffExpr{Float64, GeneralVariableRef})
            new_meas = Measure(new_func, data, Int[], Int[], false)
        else
            _remove_variable(func, gvref)
            new_meas = build_measure(func, data)
        end
        _set_core_variable_object(meas_ref, new_meas)
    end
    # Remove from dependent constraints if there are any
    for cindex in _constraint_dependencies(mref)
        cref = _temp_constraint_ref(model, cindex)
        func = JuMP.jump_function(JuMP.constraint_object(cref))
        if func isa GeneralVariableRef
            set = JuMP.moi_set(JuMP.constraint_object(cref))
            new_func = zero(JuMP.GenericAffExpr{Float64, GeneralVariableRef})
            new_constr = JuMP.ScalarConstraint(new_func, set)
            _set_core_constraint_object(cref, new_constr)
            empty!(_object_numbers(cref))
            empty!(_measure_dependencies(cref))
        else
            _remove_variable(func, gvref)
            _data_object(cref).object_nums = sort(_object_numbers(func))
            filter!(e -> e != JuMP.index(mref), _measure_dependencies(cref))
        end
    end
    # Remove from objective if used there
    if used_by_objective(mref)
        if JuMP.objective_function(model) isa GeneralVariableRef
            new_func = zero(JuMP.GenericAffExpr{Float64, GeneralVariableRef})
            JuMP.set_objective_function(model, new_func)
            JuMP.set_objective_sense(model, MOI.FEASIBILITY_SENSE)
        else
            _remove_variable(JuMP.objective_function(model), gvref)
        end
    end
    # delete associated derivative variables and mapping 
    for index in _derivative_dependencies(mref)
        JuMP.delete(model, dispatch_variable_ref(model, index))
    end
    # Update that the variables used by it are no longer used by it
    vrefs = _all_function_variables(measure_function(mref))
    union!(vrefs, parameter_refs(measure_data(mref)))
    for vref in vrefs
        filter!(e -> e != JuMP.index(mref), _measure_dependencies(vref))
    end
    # Remove any unique supports associated with this measure 
    if num_supports(measure_data(mref)) > 0
        label = support_label(measure_data(mref))
        if label <: UniqueMeasure
            delete_supports(parameter_refs(measure_data(mref)), label = label)
        end
    end
    # delete remaining measure information
    _delete_data_object(mref)
    return
end
