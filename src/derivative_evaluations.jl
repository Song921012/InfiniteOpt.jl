################################################################################
#                                HELPER METHODS
################################################################################
"""
    generate_derivative_supports(pref::IndependentParameterRef, 
                                 method::GenerativeDerivativeMethod)::Vector{Float64}

Generate and return a vector any additional supports needed by `method`. This is 
intended as an internal method and will need to be extended for user-defined 
derivative methods that are generative.
"""
function generate_derivative_supports(
    pref::IndependentParameterRef, 
    method::AbstractDerivativeMethod
    )
    error("`generate_derivative_supports` not extended for derivative method of " * 
          "type $(typeof(method)).")
end

# NonGenerativeDerivativeMethod
function generate_derivative_supports(
    pref::IndependentParameterRef, 
    method::NonGenerativeDerivativeMethod
    )::Vector{Float64}
    return Float64[]
end

## Define helper functions for Lobatto Polynomials'
# Generate the Legendre polynomials
function _legendre(n::Int)::Polynomials.Polynomial{Float64} 
    return sum(binomial(n,k)^2 * Polynomials.Polynomial([-1,1])^(n-k) * 
               Polynomials.Polynomial([1,1])^k for k in 0:n) / 2^n
end 

# Compute the Lobatto roots
function _compute_internal_node_basis(n::Int)::Vector{Float64} 
    return Polynomials.roots(Polynomials.derivative(_legendre(n+1)))
end

# OrthogonalCollocation (top level dispatch)
function generate_derivative_supports(
    pref::IndependentParameterRef, 
    method::OrthogonalCollocation
    )::Vector{Float64}
    return generate_derivative_supports(pref, method, method.technique)
end

# OrthogonalCollocation (Labatto)
function generate_derivative_supports(
    pref::IndependentParameterRef, 
    method::OrthogonalCollocation,
    technique::Type{Lobatto}
    )::Vector{Float64}
    # collect the preliminaries
    num_nodes = method.num_internal_nodes
    node_basis = _compute_internal_node_basis(num_nodes)
    ordered_supps = supports(pref, label = All) # already sorted by SortedDict
    num_supps = length(ordered_supps)
    num_supps <= 1 && error("$(pref) does not have enough supports for derivative evaluation.")
    internal_nodes = Vector{Float64}(undef, num_nodes * (num_supps - 1))
    # generate the internal node supports
    for i in Iterators.take(eachindex(ordered_supps), num_supps - 1)
        lb = ordered_supps[i]
        ub = ordered_supps[i+1]
        internal_nodes[(i-1)*num_nodes+1:i*num_nodes] = (ub - lb) / 2 * node_basis .+ (ub + lb) / 2
    end
    return internal_nodes
end

# OrthogonalCollocation (Fallback)
function generate_derivative_supports(
    pref::IndependentParameterRef, 
    method::OrthogonalCollocation,
    technique
    )
    error("Undefined orthogonal collocation technique `$technique`.")
end

"""
    add_derivative_supports(pref::Union{IndependentParameterRef, DependentParameterRef})::Nothing

Add any supports `pref` that are needed for derivative evaluation. This is intended 
as a helper method for derivative evaluation and depends [`generate_derivative_supports`](@ref InfiniteOpt.generate_derivative_supports) 
which will need to be extended for user-defined derivative methods that generate supports. 
In such cases, it is necessary to also extend 
[`support_label`](@ref InfiniteOpt.support_label(::AbstractDerivativeMethod)) Errors if 
such is not defined for the current derivative method associated with `pref`. 
"""
function add_derivative_supports(pref::IndependentParameterRef)::Nothing
    if !has_derivative_supports(pref)
        method = derivative_method(pref)
        supps = generate_derivative_supports(pref, method)
        if !isempty(supps)
            add_supports(pref, supps, label = support_label(method), check = false)
            _set_has_derivative_supports(pref, true)
        end
    end
    return
end

# Define for DependentParameterRef
function add_derivative_supports(pref::DependentParameterRef)::Nothing
    return
end

"""
    make_reduced_expr(vref::GeneralVariableRef, pref::GeneralVariableRef, 
                      support::Float64, write_model::Union{InfiniteModel, JuMP.Model})

Given the argument variable `vref` and the operator parameter `pref` from a 
derivative, build and return the reduced expression in accordance to the support 
`support` with respect to `pref`. New point/reduced variables will be written to 
`write_model`. This is solely intended as a helper function for derivative 
evaluation.
"""
function make_reduced_expr(vref::GeneralVariableRef, pref::GeneralVariableRef, 
                           support::Float64, write_model::JuMP.AbstractModel)
    return make_reduced_expr(vref, _index_type(vref), pref, support, write_model)
end

# MeasureIndex
function make_reduced_expr(mref, ::Type{MeasureIndex}, pref, support, write_model)
    data = DiscreteMeasureData(pref, [1], [support], InternalLabel, # NOTE the label will not be used
                               default_weight, NaN, NaN, false)
    return expand_measure(mref, data, write_model)
end

# TODO prevent the redundant generation of point and reduced variables for overlapping expressions
# InfiniteVariableIndex/DerivativeIndex
function make_reduced_expr(vref, 
    ::Union{Type{InfiniteVariableIndex}, Type{DerivativeIndex}}, 
    pref, support, write_model
    )::GeneralVariableRef
    prefs = parameter_list(vref)
    # only one parameter so we have to make a point variable (we know that this must be pref)
    if length(prefs) == 1
        return make_point_variable_ref(write_model, vref, [support])
    # there are other parameters so make reduced variable
    else 
        pindex = findfirst(isequal(pref), prefs)
        return make_reduced_variable_ref(write_model, vref, [pindex], [support])
    end
end

# ReducedVariableIndex
function make_reduced_expr(vref, ::Type{ReducedVariableIndex}, pref, support, 
                           write_model)::GeneralVariableRef
    # get the preliminary info
    dvref = dispatch_variable_ref(vref)
    ivref = infinite_variable_ref(vref)
    var_prefs = parameter_list(dvref)
    orig_prefs = parameter_list(ivref)
    eval_supps = eval_supports(dvref)
    pindex = findfirst(isequal(pref), orig_prefs)
    # we only have 1 parameter so we need to make a point variable
    if length(var_prefs) == 1
        processed_support = _make_point_support(orig_prefs, eval_supps, pindex, support)
        return make_point_variable_ref(write_model, ivref, processed_support)
    # otherwise we need to make a futher reduced variable
    else
        indices = collect(keys(eval_supps))
        vals = map(k -> eval_supps[k], indices)
        push!(indices, pindex)
        push!(vals, support)
        return make_reduced_variable_ref(write_model, ivref, indices, vals)
    end
end

################################################################################
#                        EVALUATE_DERIVIATIVE DEFINITIONS
################################################################################
"""
    evaluate_derivative(dref::GeneralVariableRef, 
                        method::AbstractDerivativeMethod,
                        write_model::JuMP.AbstractModel)::Vector{JuMP.AbstractJuMPScalar}

Build expressions for derivative `dref` evaluated in accordance with `method`. 
The expressions are of the form `lhs - rhs`, where `lhs` is a function of derivatives evaluated at some supports
for certain infinite parameter, and `rhs` is a function of the derivative arguments
evaluated at some supports for certain infinite parameter. For example, for finite difference
methods at point `t = 1`, `lhs` is `Δt * ∂/∂t[T(1)]`, and `rhs` could be `T(1+Δt) - T(1)` in
case of forward difference mode. This is intended as a helper function for `evaluate`, which 
will take the the expressions generated by this method and generate constraints that approximate
the derivative values by setting the expressions as 0. However, one can extend this function 
to encode custom methods for approximating derivatives. This should invoke 
`add_derivative_supports` if the method is generative and users will likely find 
it convenient to use `make_reduced_expr`.
"""
function evaluate_derivative(
    dref::GeneralVariableRef,                        
    method::AbstractDerivativeMethod,                         
    write_model::JuMP.AbstractModel)
    error("`evaluate_derivative` not defined for derivative method of type " * 
          "$(typeof(method)).")
end

## Define helper methods for finite difference 
# Forward
function _make_difference_expr(dref::GeneralVariableRef,
                               vref::GeneralVariableRef, 
                               pref::GeneralVariableRef,
                               index::Int, 
                               ordered_supps::Vector{Float64},
                               write_model::JuMP.AbstractModel, 
                               type::Type{Forward})::JuMP.AbstractJuMPScalar
    curr_value = ordered_supps[index]
    next_value = ordered_supps[index+1]
    return JuMP.@expression(_Model, (next_value - curr_value) * 
                                    make_reduced_expr(dref, pref, curr_value, write_model) -
                                    make_reduced_expr(vref, pref, next_value, write_model) +
                                    make_reduced_expr(vref, pref, curr_value, write_model))
end

# Central
function _make_difference_expr(dref::GeneralVariableRef, 
                               vref::GeneralVariableRef, 
                               pref::GeneralVariableRef,
                               index::Int, 
                               ordered_supps::Vector{Float64}, 
                               write_model::JuMP.AbstractModel, 
                               type::Type{Central})::JuMP.AbstractJuMPScalar
    prev_value = ordered_supps[index-1]
    next_value = ordered_supps[index+1]
    curr_value = ordered_supps[index]
    return JuMP.@expression(_Model, (next_value - prev_value) *  
                                    make_reduced_expr(dref, pref, curr_value, write_model) - 
                                    make_reduced_expr(vref, pref, next_value, write_model) +
                                    make_reduced_expr(vref, pref, prev_value, write_model))
end

# Backward
function _make_difference_expr(dref::GeneralVariableRef,
                               vref::GeneralVariableRef, 
                               pref::GeneralVariableRef,
                               index::Int, 
                               ordered_supps::Vector{Float64}, 
                               write_model::JuMP.AbstractModel,
                               type::Type{Backward})::JuMP.AbstractJuMPScalar
    prev_value = ordered_supps[index-1]
    curr_value = ordered_supps[index]
    return JuMP.@expression(_Model, (curr_value - prev_value) *  
                                    make_reduced_expr(dref, pref, curr_value, write_model) - 
                                    make_reduced_expr(vref, pref, curr_value, write_model) +
                                    make_reduced_expr(vref, pref, prev_value, write_model))
end

# evaluate_derivative for FiniteDifference
function evaluate_derivative(
    dref::GeneralVariableRef, 
    method::FiniteDifference, 
    write_model::JuMP.AbstractModel
    )::Vector{JuMP.AbstractJuMPScalar}
    # gather the arugment and parameter 
    vref = derivative_argument(dref)
    pref = operator_parameter(dref)
    # get the supports and check validity
    ordered_supps = sort!(supports(pref, label = All))
    n_supps = length(ordered_supps)
    n_supps <= 1 && error("$(pref) does not have enough supports for derivative evaluation.")
    # make the expressions
    exprs = Vector{JuMP.AbstractJuMPScalar}(undef, n_supps - 2)
    for i in eachindex(exprs)
        exprs[i] = _make_difference_expr(dref, vref, pref, i + 1, ordered_supps, 
                                         write_model, method.technique)
    end
    if method.add_boundary_constraint && method.technique == Forward
        push!(exprs, _make_difference_expr(dref, vref, pref, 1, ordered_supps, 
                                           write_model, Forward))
    elseif method.add_boundary_constraint && method.technique == Backward
        push!(exprs, _make_difference_expr(dref, vref, pref, n_supps, ordered_supps, 
                                           write_model, Backward))
    end
    return exprs
end

# Evaluate_derivative for OrthogonalCollocation
# This is based on the collocation scheme presented in "Nonlinear Modeling, 
# Estimation and Predictive Control in APMonitor"
function evaluate_derivative(
    dref::GeneralVariableRef, 
    method::OrthogonalCollocation, 
    write_model::JuMP.AbstractModel
    )::Vector{JuMP.AbstractJuMPScalar}
    # gather the arugment and parameter 
    vref = derivative_argument(dref)
    pref = operator_parameter(dref)
    # ensure that the internal supports are added in case they haven't already 
    add_derivative_supports(pref) # this checks for enough supports
    # gather the supports and indices of the internal supports
    all_supps = supports(pref, label = All) # sorted by virtue of SortedDict
    bool_inds = map(s -> !(support_label(method) in s), 
                    values(_parameter_supports(dispatch_variable_ref(pref))))
    interval_inds = findall(bool_inds)
    n_nodes = method.num_internal_nodes
    # compute M matrix based on the node values and generate expressions using 
    # the M matrix and `make_reduced_expr`
    exprs = Vector{JuMP.AbstractJuMPScalar}(undef, length(all_supps) - 1)
    counter = 1
    for i in Iterators.take(eachindex(interval_inds), length(interval_inds) - 1)
        # collect the supports
        lb = all_supps[interval_inds[i]]
        i_nodes = all_supps[interval_inds[i]+1:interval_inds[i+1]] .- lb
        # build the matrices in memory order (column-wise using the transpose form)
        M1t = Matrix{Float64}(undef, n_nodes+1, n_nodes+1)
        M2t = Matrix{Float64}(undef, n_nodes+1, n_nodes+1)
        for j in eachindex(i_nodes) # support index
            for k in eachindex(i_nodes) # polynomial index
                M1t[k, j] = k * i_nodes[j]^(k-1)
                M2t[k, j] = i_nodes[j]^k
            end
        end
        Minvt = M1t \ M2t
        for j in eachindex(i_nodes)
            exprs[counter] = JuMP.@expression(_Model, sum(Minvt[k, j] *  make_reduced_expr(dref, pref, i_nodes[k] + lb, write_model) 
                                                          for k in eachindex(i_nodes)) - 
                                                      make_reduced_expr(vref, pref, i_nodes[j] + lb, write_model) + 
                                                      make_reduced_expr(vref, pref, lb, write_model))
            counter += 1
        end
    end
    return exprs
end

################################################################################
#                              EVALUATION METHODS
################################################################################
"""
    evaluate(dref::DerivativeRef)::Nothing

Numerically evaluate `dref` by computing its auxiliary derivative constraints 
(e.g., collocation equations) and add them to the model. For normal usage, it is 
recommended that this method not be called directly and instead have TranscriptionOpt 
handle these equations. Errors if `evaluate_derivative` is not 
defined for the derivative method employed.

The resulting constraints can be accessed via `derivative_constraints`.

**Example**
```julia-repl
julia> m = InfiniteModel(); @infinite_parameter(m, t in [0,2]); @infinite_variable(m, T(t));

julia> dref = @deriv(T,t)
∂/∂t[T(t)]

julia> add_supports(t, [0, 0.5, 1, 1.5, 2])

julia> evaluate(dref)

julia> derivative_constraints(dref)
Feasibility
4-element Array{InfOptConstraintRef,1}:
 0.5 ∂/∂t[T(t)](0.5) - T(0.5) + T(0) = 0.0
 0.5 ∂/∂t[T(t)](1) - T(1) + T(0.5) = 0.0
 0.5 ∂/∂t[T(t)](1.5) - T(1.5) + T(1) = 0.0
 0.5 ∂/∂t[T(t)](2) - T(2) + T(1.5) = 0.0
```
"""
function evaluate(dref::DerivativeRef)::Nothing
    if !has_derivative_constraints(dref)
        # collect the basic info
        method = derivative_method(dref)
        model = JuMP.owner_model(dref)
        constr_list = _derivative_constraint_dependencies(dref)
        # get the expressions 
        gvref = GeneralVariableRef(model, JuMP.index(dref).value, DerivativeIndex)
        exprs = evaluate_derivative(gvref, method, model)
        # add the constraints
        for expr in exprs
            cref = JuMP.@constraint(model, expr == 0)
            push!(constr_list, JuMP.index(cref))
        end
        # update the parameter status 
        pref = dispatch_variable_ref(operator_parameter(dref))
        _set_has_derivative_constraints(pref, true)
    end
    return
end

"""
    evaluate_all_derivatives!(model::InfiniteModel)::Nothing

Evaluate all the derivatives in `model` by adding the corresponding auxiliary 
equations to `model`. See [`evaluate`](@ref) for more information.

**Example**
```julia-repl
julia> m = InfiniteModel();

julia> @infinite_parameter(m, t in [0,2], supports = [0, 1, 2]);

julia> @infinite_parameter(m, x in [0,1], supports = [0, 0.5, 1]);

julia> @infinite_variable(m, T(x, t));

julia> dref1 = @deriv(T, t); dref2 = @deriv(T, x^2);

julia> evaluate_all_derivatives!(m)

julia> print(m)
Feasibility
Subject to
 ∂/∂t[T(x, t)](x, 1) - T(x, 1) + T(x, 0) = 0.0, ∀ x ∈ [0, 1]
 ∂/∂t[T(x, t)](x, 2) - T(x, 2) + T(x, 1) = 0.0, ∀ x ∈ [0, 1]
 0.5 ∂/∂x[T(x, t)](0.5, t) - T(0.5, t) + T(0, t) = 0.0, ∀ t ∈ [0, 2]
 0.5 ∂/∂x[T(x, t)](1, t) - T(1, t) + T(0.5, t) = 0.0, ∀ t ∈ [0, 2]
 0.5 ∂/∂x[∂/∂x[T(x, t)]](0.5, t) - ∂/∂x[T(x, t)](0.5, t) + ∂/∂x[T(x, t)](0, t) = 0.0, ∀ t ∈ [0, 2]
 0.5 ∂/∂x[∂/∂x[T(x, t)]](1, t) - ∂/∂x[T(x, t)](1, t) + ∂/∂x[T(x, t)](0.5, t) = 0.0, ∀ t ∈ [0, 2]
```
"""
function evaluate_all_derivatives!(model::InfiniteModel)::Nothing
    for dref in all_derivatives(model)
        evaluate(dref)
    end
    return
end