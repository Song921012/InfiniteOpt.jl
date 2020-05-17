################################################################################
#                            MATH SYMBOL METHODS
################################################################################
# Support additional math symbols beyond what JuMP does
function _infopt_math_symbol(::Type{JuMP.REPLMode}, name::Symbol)::String
    if name == :intersect
        return Sys.iswindows() ? "and" : "∩"
    elseif name == :prop
        return "~"
    else
        return JuMP._math_symbol(JuMP.REPLMode, name)
    end
end

# Support additional math symbols beyond what JuMP does
function _infopt_math_symbol(::Type{JuMP.IJuliaMode}, name::Symbol)::String
    if name == :intersect
        return "\\cap"
    elseif name == :prop
        return "\\sim"
    else
        return JuMP._math_symbol(JuMP.IJuliaMode, name)
    end
end

################################################################################
#                            INFINITE SET METHODS
################################################################################
# Return "s" if n is greater than one
_plural(n) = (isone(n) ? "" : "s")

## Return the string of an infinite set
# IntervalSet
function set_string(print_mode, set::IntervalSet)::String
    return string("[", JuMP._string_round(JuMP.lower_bound(set)), ", ",
                  JuMP._string_round(JuMP.upper_bound(set)), "]")
end

# DistributionSet
function set_string(print_mode, set::DistributionSet)::String
    return string(set.distribution)
end

# CollectionSet
function set_string(print_mode, set::CollectionSet)::String
    sets = collection_sets(set)
    num_sets = length(sets)
    cs_string = string("CollectionSet with ", num_sets, " set",
                       _plural(num_sets), ":")
    for s in sets
        cs_string *= string("\n ", set_string(print_mode, s))
    end
    return cs_string
end

# Fallback
function set_string(print_mode, set::S) where {S <: AbstractInfiniteSet}
    # hack fix because just calling `string(set)` --> StackOverflow Error
    values = map(f -> getfield(set, f), fieldnames(S))
    return string(S, "(", join(values, ", "), ")")
end

## Return in set strings of infinite sets
# Extend to return of in set string for interval sets
function JuMP.in_set_string(print_mode, set::IntervalSet)::String
    if JuMP.lower_bound(set) != JuMP.upper_bound(set)
        return string(_infopt_math_symbol(print_mode, :in), " ",
                      set_string(print_mode, set))
    else
        return string(_infopt_math_symbol(print_mode, :eq), " ",
                      JuMP._string_round(JuMP.lower_bound(set)))
    end
end

# Extend to return of in set string for distribution sets
function JuMP.in_set_string(print_mode, set::DistributionSet)::String
    dist = set.distribution
    name = string(typeof(dist))
    bracket_index = findfirst(isequal('{'), name)
    if bracket_index !== nothing
        name = name[1:bracket_index-1]
    end
    if !isempty(size(dist))
        dims = size(dist)
        name *= string("(dim", _plural(length(dims)), ": (", join(dims, ", "), "))")
    end
    return string(_infopt_math_symbol(print_mode, :prop), " ", name)
end

# Extend to return of in set string of other sets
function JuMP.in_set_string(print_mode, set::AbstractInfiniteSet)::String
    return string(_infopt_math_symbol(print_mode, :in), " ",
                  set_string(print_mode, set))
end

## Extend in set string to consider parameter bounds
# IntervalSet
function JuMP.in_set_string(print_mode,
    pref::GeneralVariableRef,
    set::IntervalSet,
    bounds::ParameterBounds{GeneralVariableRef})::String
    # determine if in bounds
    in_bounds = haskey(bounds, pref)
    # make the string
    interval = in_bounds ? bounds[pref] : set
    return JuMP.in_set_string(print_mode, interval)
end

# InfiniteScalarSet
function JuMP.in_set_string(print_mode,
    pref::GeneralVariableRef,
    set::InfiniteScalarSet,
    bounds::ParameterBounds{GeneralVariableRef})::String
    # determine if in bounds
    if haskey(bounds, pref)
        bound_set = bounds[pref]
        if JuMP.lower_bound(bound_set) == JuMP.upper_bound(bound_set)
            return JuMP.in_set_string(print_mode, bound_set)
        else
            return  string(JuMP.in_set_string(print_mode, set), " ",
                           _infopt_math_symbol(print_mode, :intersect),
                           " ", set_string(print_mode, bound_set))
        end
    else
        return JuMP.in_set_string(print_mode, set)
    end
end

################################################################################
#                           MEASURE STRING METHODS
################################################################################
## Convert measure data into a useable string for measure printing
# 1-D DiscreteMeasureData/FunctionalDiscreteMeasureData
function measure_data_string(print_mode,
    data::Union{DiscreteMeasureData{GeneralVariableRef},
                FunctionalDiscreteMeasureData{GeneralVariableRef}}
    )::String
    pref = parameter_refs(data)
    lb = JuMP.lower_bound(data)
    ub = JuMP.upper_bound(data)
    nan_bound = isnan(lb) || isnan(ub)
    if nan_bound
        return JuMP.function_string(print_mode, pref)
    else
        set = IntervalSet(lb, ub)
        return string(JuMP.function_string(print_mode, pref), " ",
                      JuMP.in_set_string(print_mode, set))
    end
end

# Multi-D DiscreteMeasureData/FunctionalDiscreteMeasureData
function measure_data_string(print_mode,
    data::Union{DiscreteMeasureData{Vector{GeneralVariableRef}},
                FunctionalDiscreteMeasureData{Vector{GeneralVariableRef}}}
    )::String
    prefs = parameter_refs(data)
    lbs = JuMP.lower_bound(data)
    ubs = JuMP.upper_bound(data)
    has_bounds = !isnan(first(lbs)) && !isnan(first(ubs))
    homo_bounds = has_bounds && _allequal(lbs) && _allequal(ubs)
    names = map(p -> _remove_name_index(p), prefs)
    homo_names = _allequal(names)
    num_prefs = length(prefs)
    if homo_names && homo_bounds
        set = IntervalSet(first(lbs), first(ubs))
        return string(first(names), " ", JuMP.in_set_string(print_mode, set),
                      "^", num_prefs)
    elseif has_bounds
        str_list = [JuMP.function_string(print_mode, prefs[i]) * " " *
                    JuMP.in_set_string(print_mode, IntervalSet(lbs[i], ubs[i]))
                    for i in eachindex(prefs)]
        return _make_str_value(str_list)[2:end-1]
    elseif homo_names
        return first(names)
    else
        return _make_str_value(prefs)
    end
end

# Fallback
function measure_data_string(print_mode, data::AbstractMeasureData)::String
    prefs = parameter_refs(data)
    names = map(p -> _remove_name_index(p), prefs)
    if _allequal(names)
        return first(names)
    else
        return _make_str_value(prefs)
    end
end

# Make strings to represent measures in REPLMode
function JuMP.function_string(::Type{JuMP.REPLMode}, mref::MeasureRef)::String
    data = measure_data(mref)
    data_str = measure_data_string(JuMP.REPLMode, data)
    func_str = JuMP.function_string(JuMP.REPLMode, measure_function(mref))
    return string(JuMP.name(mref), "{", data_str, "}[", func_str, "]")
end

# Make strings to represent measures in IJuliaMode
function JuMP.function_string(::Type{JuMP.IJuliaMode}, mref::MeasureRef)::String
    data = measure_data(mref)
    data_str = measure_data_string(JuMP.IJuliaMode, data)
    func_str = JuMP.function_string(JuMP.IJuliaMode, measure_function(mref))
    return string(JuMP.name(mref), "_{", data_str, "}[", func_str, "]")
end

# TODO make specifc methods for decision variables so we don't generate them at creation

################################################################################
#                         CONSTRAINT STRING METHODS
################################################################################
# Return parameter bound list as a string
function bound_string(print_mode, bounds::ParameterBounds{GeneralVariableRef}
                      )::String
    string_list = ""
    for (pref, set) in bounds
        string_list *= string(JuMP.function_string(print_mode, pref), " ",
                              JuMP.in_set_string(print_mode, set), ", ")
    end
    return string_list[1:end-2]
end

## Return the parameter domain string given the object index
# IndependentParameter
function _param_domain_string(print_mode, model::InfiniteModel,
                              index::IndependentParameterIndex,
                              bounds::ParameterBounds{GeneralVariableRef}
                              )::String
    pref = dispatch_variable_ref(model, index)
    set = infinite_set(pref)
    gvref = GeneralVariableRef(model, MOIUC.key_to_index(index), typeof(index))
    return string(JuMP.function_string(print_mode, pref), " ",
                  JuMP.in_set_string(print_mode, gvref, set, bounds))
end

# DependentParameters
function _param_domain_string(print_mode, model::InfiniteModel,
                              index::DependentParametersIndex,
                              bounds::ParameterBounds{GeneralVariableRef}
                              )::String
    # parse the infinite set
    first_gvref = GeneralVariableRef(model, MOIUC.key_to_index(index),
                                     DependentParameterIndex, 1)
    set = _parameter_set(dispatch_variable_ref(first_gvref))
    # iterate over the individual scalar sets if is a collection set
    if set isa CollectionSet
        domain_str = ""
        for i in eachindex(collection_sets(set))
            sset = collection_sets(set)[i]
            gvref = GeneralVariableRef(model, MOIUC.key_to_index(index),
                                       DependentParameterIndex, i)
            domain_str *= string(JuMP.function_string(print_mode, gvref), " ",
                        JuMP.in_set_string(print_mode, gvref, sset, bounds), ", ")
        end
        domain_str = domain_str[1:end-2]
    else
        # determine if bounds contain equalities and filter to the bounds of interest
        is_eq = haskey(bounds, first_gvref) && JuMP.lower_bound(bounds[first_gvref]) == JuMP.upper_bound(bounds[first_gvref])
        filtered_bounds = filter(e -> e[1].raw_index == MOIUC.key_to_index(index) &&
                                 e[1].index_type == DependentParameterIndex, bounds)
        # build the domain string
        if is_eq
            domain_str = bound_string(print_mode, filtered_bounds)
        else
            domain_str = string(_remove_name_index(first_gvref), " ",
                            JuMP.in_set_string(print_mode, set))
            if !isempty(filtered_bounds)
                domain_str *= string(" ", _infopt_math_symbol(print_mode, :intersect),
                                     " (", bound_string(print_mode, filtered_bounds), ")")
            end
        end
    end
    return domain_str
end

# Return string of an infinite constraint
function JuMP.constraint_string(print_mode, cref::InfOptConstraintRef;
                                in_math_mode = false)::String
    # get the function and set strings
    func_str = JuMP.function_string(print_mode, _core_constraint_object(cref))
    in_set_str = JuMP.in_set_string(print_mode, _core_constraint_object(cref))
    # check if constraint if finite
    obj_nums = _object_numbers(cref)
    if isempty(obj_nums)
        bound_str = ""
    else
        # get the parameter bounds if there are any
        if has_parameter_bounds(cref)
            bounds = parameter_bounds(cref)
        else
            bounds = ParameterBounds()
        end
        # prepare the parameter domains
        model = JuMP.owner_model(cref)
        bound_str = string(", ", JuMP._math_symbol(print_mode, :for_all), " ")
        for index in _param_object_indices(model)[_object_numbers(cref)]
            bound_str *= string(_param_domain_string(print_mode, model, index, bounds),
                                ", ")
        end
        bound_str = bound_str[1:end-2]
    end
    # form the constraint string
    if print_mode == JuMP.REPLMode
        lines = split(func_str, '\n')
        lines[1 + div(length(lines), 2)] *= " " * in_set_str * bound_str
        constr_str = join(lines, '\n')
    else
        constr_str = string(func_str, " ", in_set_str, bound_str)
    end
    # format for IJulia
    if print_mode == JuMP.IJuliaMode && !in_math_mode
        constr_str = JuMP._wrap_in_inline_math_mode(constr_str)
    end
    # add name if it has one
    name = JuMP.name(cref)
    if isempty(name) || (print_mode == JuMP.IJuliaMode && in_math_mode)
        return constr_str
    else
        return string(name, " : ", constr_str)
    end
end

# return list of constraint
function JuMP.constraints_string(print_mode, model::InfiniteModel)::Vector{String}
    # allocate the string vector
    strings = Vector{String}(undef, JuMP.num_constraints(model))
    # produce a string for each constraint
    counter = 1
    for (index, object) in model.constraints
        cref = _make_constraint_ref(model, index)
        strings[counter] = JuMP.constraint_string(print_mode, cref,
                                                  in_math_mode = true)
        counter += 1
    end
    return strings
end

################################################################################
#                           OBJECTIVE STRING METHODS
################################################################################
# Return the objective string
function JuMP.objective_function_string(print_mode, model::InfiniteModel)
    return JuMP.function_string(print_mode, JuMP.objective_function(model))
end

################################################################################
#                           DATATYPE SHOWING METHODS
################################################################################
# Show infinite sets in REPLMode
function Base.show(io::IO, set::AbstractInfiniteSet)
    print(io, set_string(JuMP.REPLMode, set))
    return
end

# Show infinite sets in IJuliaMode
function Base.show(io::IO, ::MIME"text/latex", set::AbstractInfiniteSet)
    print(io, set_string(JuMP.IJuliaMode, set))
end

# TODO use ... when necessary --> Subdomain bounds: t in [0, 1], x[1] == 0, x[2] == 0, ... x[6] == 0, a in [2, 3]
# Show ParameterBounds in REPLMode
function Base.show(io::IO, bounds::ParameterBounds)
    print(io, "Subdomain bounds (", length(bounds), "): ",
          bound_string(JuMP.REPLMode, bounds))
    return
end

# Show ParameterBounds in IJuliaMode
function Base.show(io::IO, ::MIME"text/latex", bounds::ParameterBounds)
    print(io, "Subdomain bounds (", length(bounds), "): ",
          bound_string(JuMP.IJuliaMode, bounds))
end

# Show GeneralVariableRefs via their DispatchVariableRef in REPLMode
function Base.show(io::IO, vref::GeneralVariableRef)
    print(io, JuMP.function_string(JuMP.REPLMode, dispatch_variable_ref(vref)))
    return
end

# Show GeneralVariableRefs via their DispatchVariableRef in IJuliaMode
function Base.show(io::IO, ::MIME"text/latex", vref::GeneralVariableRef)
    print(io, JuMP.function_string(JuMP.IJuliaMode, dispatch_variable_ref(vref)))
end

# Show constraint in REPLMode
function Base.show(io::IO, ref::InfOptConstraintRef)
    print(io, JuMP.constraint_string(JuMP.REPLMode, ref))
    return
end

# Show constraint in IJuliaMode
function Base.show(io::IO, ::MIME"text/latex", ref::InfOptConstraintRef)
    print(io, JuMP.constraint_string(JuMP.IJuliaMode, ref))
end

# Show the backend information associated with the optimizer model
function JuMP.show_backend_summary(io::IO, model::InfiniteModel)
    println(io, "Optimizer model backend information: ")
    JuMP.show_backend_summary(io, optimizer_model(model))
    return
end

# Show the objective function type
function JuMP.show_objective_function_summary(io::IO, model::InfiniteModel)
    println(io, "Objective function type: ",
            JuMP.objective_function_type(model))
    return
end

# Return constraint summary in JuMP like manner
function JuMP.show_constraints_summary(io::IO, model::InfiniteModel)
    for (F, S) in JuMP.list_of_constraint_types(model)
        n_constraints = JuMP.num_constraints(model, F, S)
        println(io, "`$F`-in-`$S`: $n_constraints constraint",
                _plural(n_constraints))
    end
    return
end

# Have the infinitemodel object show similar to Model
function Base.show(io::IO, model::InfiniteModel)
    # indicate is an infinite model
    println(io, "An InfiniteOpt Model")
    # show objective ssnse info
    sense = JuMP.objective_sense(model)
    if sense == MOI.MAX_SENSE
        print(io, "Maximization")
    elseif sense == MOI.MIN_SENSE
        print(io, "Minimization")
    else
        print(io, "Feasibility")
    end
    println(io, " problem with:")
    # show finite parameter info
    num_finite_params = num_parameters(model, FiniteParameter)
    println(io, "Finite Parameter", _plural(num_finite_params), ": ",
            num_finite_params)
    # show infinite parameter info
    num_infinite_params = num_parameters(model, InfiniteParameter)
    println(io, "Infinite Parameter", _plural(num_infinite_params), ": ",
            num_infinite_params)
    # show variable info
    num_vars = JuMP.num_variables(model)
    println(io, "Variable", _plural(num_vars), ": ", num_vars)
    # show objective function info
    if sense != MOI.FEASIBILITY_SENSE
        JuMP.show_objective_function_summary(io, model)
    end
    # show constraint info
    JuMP.show_constraints_summary(io, model)
    # show other info
    names_in_scope = sort!(collect(keys(JuMP.object_dictionary(model))))
    if !isempty(names_in_scope)
        print(io, "Names registered in the model: ",
              join(string.(names_in_scope), ", "), "\n")
    end
    JuMP.show_backend_summary(io, model)
end
