################################################################################
#                   CORE DISPATCHVARIABLEREF METHOD EXTENSIONS
################################################################################
# Extend dispatch_variable_ref
function dispatch_variable_ref(model::InfiniteModel,
                               index::ReducedInfiniteVariableIndex
                               )::ReducedInfiniteVariableRef
    return ReducedInfiniteVariableRef(model, index)
end

# Extend _add_data_object
function _add_data_object(model::InfiniteModel,
                          object::VariableData{<:ReducedInfiniteVariable}
                          )::ReducedInfiniteVariableIndex
    return MOIUC.add_item(model.reduced_vars, object)
end

# Extend _data_dictionary (type based)
function _data_dictionary(model::InfiniteModel, ::Type{ReducedInfiniteVariable}
    )::MOIUC.CleverDict{ReducedInfiniteVariableIndex, VariableData{ReducedInfiniteVariable{GeneralVariableRef}}}
    return model.reduced_vars
end

# Extend _data_dictionary (reference based)
function _data_dictionary(vref::ReducedInfiniteVariableRef
    )::MOIUC.CleverDict{ReducedInfiniteVariableIndex, VariableData{ReducedInfiniteVariable{GeneralVariableRef}}}
    return JuMP.owner_model(vref).reduced_vars
end

# Extend _data_object
function _data_object(vref::ReducedInfiniteVariableRef)::VariableData{<:ReducedInfiniteVariable}
    return _data_dictionary(vref)[JuMP.index(vref)]
end

# Extend _core_variable_object
function _core_variable_object(vref::ReducedInfiniteVariableRef)::ReducedInfiniteVariable
    return _data_object(vref).variable
end

# Extend _object_numbers
function _object_numbers(vref::ReducedInfiniteVariableRef)::Vector{Int}
    return _core_variable_object(vref).object_nums
end

# Extend _parameter_numbers
function _parameter_numbers(vref::ReducedInfiniteVariableRef)::Vector{Int}
    par_set = Set{Int}()
    prefs = raw_parameter_refs(infinite_variable_ref(vref))
    for i in eachindex(prefs)
        if !haskey(eval_supports(vref), i)
            push!(par_set, _parameter_number(prefs[i]))
        end
    end
    return
end

################################################################################
#                             DEFINITION METHODS
################################################################################
"""
    JuMP.build_variable(_error::Function, ivref::GeneralVariableRef,
                        eval_supports::Dict{Int, Float64}; [check::Bool = true]
                        )::ReducedInfiniteVariable{GeneralVariableRef}

Extend the `JuMP.build_variable` function to build a reduced infinite variable
based on the infinite variable `ivref` with reduction support `eval_supports`.
Will check that input is appropriate if `check = true`. Errors if `ivref` is
not an infinite variable, `eval_supports` violate infinite parameter domains, or
if the support dimensions don't match the infinite parameter dimensions of `ivref`.
This is intended an internal method for use in evaluating measures.
"""
function JuMP.build_variable(_error::Function, ivref::GeneralVariableRef,
                             eval_supports::Dict{Int, Float64};
                             check::Bool = true
                             )::ReducedInfiniteVariable{GeneralVariableRef}
    # check the inputs
    dvref = dispatch_variable_ref(ivref)
    prefs = raw_parameter_refs(dvref)
    if check
        if !(dvref isa InfiniteVariableRef)
             _error("Must specify an infinite variable dependency.")
        elseif maximum(keys(eval_supports)) > length(parameter_list(dvref))
            _error("Support evaluation dictionary indices do not the infinite " *
                   "parameter dependencies of $(ivref).")
        end
        for (index, value) in eval_supports
            if has_lower_bound(prefs[index]) && !supports_in_set(value, infinite_set(pref))
                _error("Evaluation support violates infinite parameter domain(s).")
            end
        end
    end
    # get the parameter object numbers of the dependencies
    object_set = Set{Int}()
    for i in eachindex(prefs)
        if !haskey(eval_supports, i)
            push!(object_set, _object_number(prefs[i]))
        end
    end
    return ReducedInfiniteVariable(ivref, eval_supports, collect(object_set))
end

"""
    JuMP.add_variable(model::InfiniteModel, var::ReducedInfiniteVariable,
                      [name::String = ""; define_name = true]
                      )::GeneralVariableRef

Extend the [`JuMP.add_variable`](@ref JuMP.add_variable(::JuMP.Model, ::JuMP.ScalarVariable, ::String))
function to accomodate `InfiniteOpt` reduced variable types. Adds `var` to the
infinite model `model` and returns a [`GeneralVariableRef`](@ref).
Primarily intended to be an internal function used in evaluating measures. A name
will be generated using the supports if `define_name = true`.
"""
function JuMP.add_variable(model::InfiniteModel, var::ReducedInfiniteVariable,
                           name::String = "";
                           define_name::Bool = true)::GeneralVariableRef
    JuMP.check_belongs_to_model(var.infinite_variable_ref)
    data_object = VariableData(v)
    vindex = _add_data_object(model, data_object)
    if length(name) != 0 || define_name
        JuMP.set_name(ReducedInfiniteVariableRef(model, vindex), name)
    end
    gvref = GeneralVariableRef(model, vindex.value, typeof(vindex))
    return gvref
end

################################################################################
#                          PARAMETER REFERENCE METHODS
################################################################################
"""
    infinite_variable_ref(vref::ReducedInfiniteVariableRef)::GeneralVariableRef

Return the infinite variable reference associated with the reduced infinite variable
`vref`.

**Example**
```julia-repl
julia> infinite_variable_ref(vref)
g(t, x)
```
"""
function infinite_variable_ref(vref::ReducedInfiniteVariableRef)::GeneralVariableRef
    return _core_variable_object(vref).infinite_variable_ref
end

"""
    eval_supports(vref::ReducedInfiniteVariableRef)::Dict{Int, Float64}

Return the evaluation supports associated with the reduced infinite variable
`vref`.

**Example**
```julia-repl
julia> eval_supports(vref)
Dict{Int64,Float64} with 1 entry:
  1 => 0.5
```
"""
function eval_supports(vref::ReducedInfiniteVariableRef)::Dict{Int, Float64}
    return _core_variable_object(vref).eval_supports
end

"""
    raw_parameter_refs(vref::ReducedInfiniteVariableRef)::VectorTuple{GeneralVariableRef}

Return the raw [`VectorTuple`](@ref) of the parameter references that `vref`
depends on. This is primarily an internal method where
[`parameter_refs`](@ref parameter_refs(vref::ReducedInfiniteVariableRef))
is intended as the preferred user function.
"""
function raw_parameter_refs(vref::ReducedInfiniteVariableRef
                            )::VectorTuple{GeneralVariableRef}
    orig_prefs = raw_parameter_refs(infinite_variable_ref(vref))
    eval_supps = eval_supports(vref)
    delete_indices = [haskey(eval_supps, i) for i = 1:length(orig_prefs)]
    return deleteat!(copy(orig_prefs), delete_indices)
end

"""
    parameter_refs(vref::ReducedInfiniteVariableRef)::Tuple

Return the infinite parameter references associated with the reduced infinite variable
`vref`. This is formatted as a `Tuple` of containing the parameter references as
they were inputted to define the untranscripted infinite variable except, the
evaluated parameters are excluded.

**Example**
```julia-repl
julia> parameter_refs(vref)
(t, [x[1], x[2]])
```
"""
function parameter_refs(vref::ReducedInfiniteVariableRef)::Tuple
    return Tuple(raw_parameter_refs(vref))
end

"""
    parameter_list(vref::ReducedInfiniteVariableRef)::Vector{GeneralVariableRef}

Return a vector of the parameter references that `vref` depends on. This is
primarily an internal method where [`parameter_refs`](@ref parameter_refs(vref::ReducedInfiniteVariableRef))
is intended as the preferred user function.
"""
function parameter_list(vref::ReducedInfiniteVariableRef)::Vector{GeneralVariableRef}
    orig_prefs = raw_parameter_refs(infinite_variable_ref(vref))
    eval_supps = eval_supports(vref)
    indices = [!haskey(eval_supps, i) for i in eachindex(orig_prefs)]
    return orig_prefs[indices]
end

################################################################################
#                                NAME METHODS
################################################################################
"""
    JuMP.set_name(vref::ReducedInfiniteVariableRef, name::String = "")::Nothing

Extend `JuMP.set_name` to set name of reduced infinite variable references. This
is primarily an internal method sense such variables are generated via expanding
measures.
"""
function JuMP.set_name(vref::ReducedInfiniteVariableRef,
                       name::String = "")::Nothing
    if length(name) == 0
        ivref = dispatch_variable_ref(infinite_variable_ref(vref))
        root_name = _root_name(ivref)
        prefs = raw_parameter_refs(ivref)
        eval_supps = eval_supports(vref)
        raw_list = [i in keys(eval_supps) ? eval_supps[i] : prefs[i]
                    for i in eachindex(prefs)]
        param_name_tuple = "("
        for i in 1:size(prefs, 1)
            value = raw_list[prefs.ranges[i]]
            if i != size(prefs, 1)
                param_name_tuple *= string(_make_str_value(value), ", ")
            else
                param_name_tuple *= string(_make_str_value(value), ")")
            end
        end
        name = string(root_name, param_name_tuple)
    end
    _data_object(vref).name = name
    JuMP.owner_model(vref).name_to_var = nothing
    return
end

"""
    JuMP.name(vref::ReducedInfiniteVariableRef)::String

Extend `JuMP.name` to return the name of reduced infinite variable references.
This will also automatically write a name if one has not yet been assigned.

**Example**
```julia-repl
julia> name(vref)
"x(t, [0, 0])"
```
"""
function JuMP.name(vref::ReducedInfiniteVariableRef)::String
    # make and set the name if that has not already been done
    if length(_data_object(vref).name) == 0
        JuMP.set_name(vref)
    end
    return _data_object(vref).name
end

################################################################################
#                            VARIABLE INFO METHODS
################################################################################
"""
    JuMP.has_lower_bound(vref::ReducedInfiniteVariableRef)::Bool

Extend [`JuMP.has_lower_bound`](@ref) to return a `Bool` whether the original
infinite variable of `vref` has a lower bound.

**Example**
```julia-repl
julia> has_lower_bound(vref)
true
```
"""
function JuMP.has_lower_bound(vref::ReducedInfiniteVariableRef)::Bool
    return JuMP.has_lower_bound(infinite_variable_ref(vref))
end

"""
    JuMP.lower_bound(vref::ReducedInfiniteVariableRef)::Float64

Extend [`JuMP.lower_bound`](@ref) to return the lower bound of the original
infinite variable of `vref`. Errors if `vref` doesn't have a lower bound.

**Example**
```julia-repl
julia> lower_bound(vref)
0.0
```
"""
function JuMP.lower_bound(vref::ReducedInfiniteVariableRef)::Float64
    ivref = dispatch_variable_ref(infinite_variable_ref(vref))
    if !JuMP.has_lower_bound(ivref)
        error("Variable $(vref) does not have a lower bound.")
    end
    return JuMP.lower_bound(ivref)
end

# Extend to return the index of the lower bound constraint associated with the
# original infinite variable of `vref`.
function JuMP._lower_bound_index(vref::ReducedInfiniteVariableRef)::ConstraintIndex
    ivref = dispatch_variable_ref(infinite_variable_ref(vref))
    if !JuMP.has_lower_bound(ivref)
        error("Variable $(vref) does not have a lower bound.")
    end
    return JuMP._lower_bound_index(ivref)
end

"""
    JuMP.LowerBoundRef(vref::ReducedInfiniteVariableRef)::InfOptConstraintRef

Extend [`JuMP.LowerBoundRef`](@ref) to extract a constraint reference for the
lower bound of the original infinite variable of `vref`.

**Example**
```julia-repl
julia> cref = LowerBoundRef(vref)
var >= 0.0
```
"""
function JuMP.LowerBoundRef(vref::ReducedInfiniteVariableRef)::InfOptConstraintRef
    return JuMP.LowerBoundRef(infinite_variable_ref(vref))
end

"""
    JuMP.has_upper_bound(vref::ReducedInfiniteVariableRef)::Bool

Extend [`JuMP.has_upper_bound`](@ref) to return a `Bool` whether the original
infinite variable of `vref` has an upper bound.

**Example**
```julia-repl
julia> has_upper_bound(vref)
true
```
"""
function JuMP.has_upper_bound(vref::ReducedInfiniteVariableRef)::Bool
    return JuMP.has_upper_bound(infinite_variable_ref(vref))
end

"""
    JuMP.upper_bound(vref::ReducedInfiniteVariableRef)::Float64

Extend [`JuMP.upper_bound`](@ref) to return the upper bound of the original
infinite variable of `vref`. Errors if `vref` doesn't have a upper bound.

**Example**
```julia-repl
julia> upper_bound(vref)
0.0
```
"""
function JuMP.upper_bound(vref::ReducedInfiniteVariableRef)::Float64
    ivref = dispatch_variable_ref(infinite_variable_ref(vref))
    if !JuMP.has_upper_bound(ivref)
        error("Variable $(vref) does not have a upper bound.")
    end
    return JuMP.upper_bound(ivref)
end

# Extend to return the index of the upper bound constraint associated with the
# original infinite variable of `vref`.
function JuMP._upper_bound_index(vref::ReducedInfiniteVariableRef)::ConstraintIndex
    ivref = dispatch_variable_ref(infinite_variable_ref(vref))
    if !JuMP.has_upper_bound(ivref)
        error("Variable $(vref) does not have a upper bound.")
    end
    return JuMP._upper_bound_index(ivref)
end

"""
    JuMP.UpperBoundRef(vref::ReducedInfiniteVariableRef)::InfOptConstraintRef

Extend [`JuMP.UpperBoundRef`](@ref) to extract a constraint reference for the
upper bound of the original infinite variable of `vref`.

**Example**
```julia-repl
julia> cref = UpperBoundRef(vref)
var <= 1.0
```
"""
function JuMP.UpperBoundRef(vref::ReducedInfiniteVariableRef)::InfOptConstraintRef
    return JuMP.UpperBoundRef(infinite_variable_ref(vref))
end

"""
    JuMP.is_fixed(vref::ReducedInfiniteVariableRef)::Bool

Extend [`JuMP.is_fixed`](@ref) to return `Bool` whether the original infinite
variable of `vref` is fixed.

**Example**
```julia-repl
julia> is_fixed(vref)
true
```
"""
function JuMP.is_fixed(vref::ReducedInfiniteVariableRef)::Bool
    return JuMP.is_fixed(infinite_variable_ref(vref))
end

"""
    JuMP.fix_value(vref::ReducedInfiniteVariableRef)::Float64

Extend [`JuMP.fix_value`](@ref) to return the fix value of the original infinite
variable of `vref`. Errors if variable is not fixed.

**Example**
```julia-repl
julia> fix_value(vref)
0.0
```
"""
function JuMP.fix_value(vref::ReducedInfiniteVariableRef)::Float64
    ivref = dispatch_variable_ref(infinite_variable_ref(vref))
    if !JuMP.is_fixed(ivref)
        error("Variable $(vref) is not fixed.")
    end
    return JuMP.fix_value(ivref)
end

# Extend to return the index of the fix constraint associated with the original
# infinite variable of `vref`.
function JuMP._fix_index(vref::ReducedInfiniteVariableRef)::ConstraintIndex
    ivref = dispatch_variable_ref(infinite_variable_ref(vref))
    if !JuMP.is_fixed(ivref)
        error("Variable $(vref) is not fixed.")
    end
    return JuMP._fix_index(ivref)
end

"""
    JuMP.FixRef(vref::ReducedInfiniteVariableRef)::InfOptConstraintRef

Extend [`JuMP.FixRef`](@ref) to return the constraint reference of the fix
constraint associated with the original infinite variable of `vref`. Errors
`vref` is not fixed.

**Examples**
```julia-repl
julia> cref = FixRef(vref)
var == 1.0
```
"""
function JuMP.FixRef(vref::ReducedInfiniteVariableRef)::InfOptConstraintRef
    return JuMP.FixRef(infinite_variable_ref(vref))
end

"""
    JuMP.start_value(vref::ReducedInfiniteVariableRef)::Union{Nothing, Float64}

Extend [`JuMP.start_value`](@ref) to return starting value of the original
infinite variable of `vref` if it has one. Returns `nothing` otherwise.

**Example**
```julia-repl
julia> start_value(vref)
0.0
```
"""
function JuMP.start_value(vref::ReducedInfiniteVariableRef)::Union{Nothing, Float64}
    return JuMP.start_value(infinite_variable_ref(vref))
end

"""
    JuMP.is_binary(vref::ReducedInfiniteVariableRef)::Bool

Extend [`JuMP.is_binary`](@ref) to return `Bool` whether the original infinite
variable of `vref` is binary.

**Example**
```julia-repl
julia> is_binary(vref)
true
```
"""
function JuMP.is_binary(vref::ReducedInfiniteVariableRef)::Bool
    return JuMP.is_binary(infinite_variable_ref(vref))
end

# Extend to return the index of the binary constraint associated with the
# original infinite variable of `vref`.
function JuMP._binary_index(vref::ReducedInfiniteVariableRef)::ConstraintIndex
    ivref = dispatch_variable_ref(infinite_variable_ref(vref))
    if !JuMP.is_binary(ivref)
        error("Variable $(vref) is not binary.")
    end
    return JuMP._binary_index(vref)
end

"""
    JuMP.BinaryRef(vref::ReducedInfiniteVariableRef)::InfOptConstraintRef

Extend [`JuMP.BinaryRef`](@ref) to return a constraint reference to the
constraint constrainting the original infinite variable of `vref` to be binary.
Errors if one does not exist.

**Example**
```julia-repl
julia> cref = BinaryRef(vref)
var binary
```
"""
function JuMP.BinaryRef(vref::ReducedInfiniteVariableRef)::InfOptConstraintRef
    return JuMP.BinaryRef(infinite_variable_ref(vref))
end

"""
    JuMP.is_integer(vref::ReducedInfiniteVariableRef)::Bool

Extend [`JuMP.is_integer`](@ref) to return `Bool` whether the original infinite
variable of `vref` is integer.

**Example**
```julia-repl
julia> is_integer(vref)
true
```
"""
function JuMP.is_integer(vref::ReducedInfiniteVariableRef)::Bool
    return JuMP.is_integer(infinite_variable_ref(vref))
end

# Extend to return the index of the integer constraint associated with the
# original infinite variable of `vref`.
function JuMP._integer_index(vref::ReducedInfiniteVariableRef)::ConstraintIndex
    ivref = dispatch_variable_ref(infinite_variable_ref(vref))
    if !JuMP.is_integer(ivref)
        error("Variable $(vref) is not an integer.")
    end
    return JuMP._integer_index(ivref)
end

"""
    JuMP.IntegerRef(vref::ReducedInfiniteVariableRef)::InfOptConstraintRef

Extend [`JuMP.IntegerRef`](@ref) to return a constraint reference to the
constraint constrainting the original infinite variable of `vref` to be integer.
Errors if one does not exist.

**Example**
```julia-repl
julia> cref = IntegerRef(vref)
var integer
```
"""
function JuMP.IntegerRef(vref::ReducedInfiniteVariableRef)::InfOptConstraintRef
    return JuMP.IntegerRef(infinite_variable_ref(vref))
end

################################################################################
#                                  DELETION
################################################################################
# Extend _delete_variable_dependencies (for use with JuMP.delete)
function _delete_variable_dependencies(vref::ReducedInfiniteVariableRef)::Nothing
    # remove mapping to infinite variable
    ivref = dispatch_variable_ref(infinite_variable_ref(vref))
    filter!(e -> e != JuMP.index(vref), _reduced_variable_dependencies(ivref))
    return
end
