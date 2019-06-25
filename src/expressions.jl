# Define type hierchical parser
function _var_type_parser(V::Type{<: JuMP.AbstractVariableRef}, W::Type{<: JuMP.AbstractVariableRef})
    if V == W
        return V
    elseif V isa Type{<: FiniteVariableRef} && W isa Type{<: FiniteVariableRef}
        return FiniteVariableRef
    elseif V isa Type{<: MeasureFiniteVariableRef} && W isa Type{<: MeasureFiniteVariableRef}
        return MeasureFiniteVariableRef
    elseif V isa Type{<: GeneralVariableRef} && W isa Type{<: GeneralVariableRef}
        return GeneralVariableRef
    else
        return JuMP.AbstractVariableRef
    end
end

# Extend handle mixed variable input
function JuMP.add_to_expression!(quad::JuMP.GenericQuadExpr{C, Z}, new_coef::C,
                                 new_var1::V, new_var2::W) where {C, Z <: JuMP.AbstractVariableRef, V, W}
    type = _var_type_parser(Z, W)
    key = JuMP.UnorderedPair{type}(new_var1, new_var2)
    JuMP._add_or_set!(quad.terms, key, new_coef)
    return quad
end

# Extend for mized aff expressions
function JuMP.add_to_expression!(aff::JuMP.GenericAffExpr{C, V}, coef::Real,
                                 other::JuMP.GenericAffExpr{C, W}) where {C, V <: JuMP.AbstractVariableRef, W}
    type = _var_type_parser(V, W)
    aff = JuMP.GenericAffExpr{C, type}(aff.constant, aff.terms)
    other = JuMP.GenericAffExpr{C, type}(other.constant, other.terms)
    JuMP.sizehint!(aff, length(JuMP.linear_terms(aff)) + length(JuMP.linear_terms(other)))
    for (term_coef, var) in JuMP.linear_terms(other)
        JuMP._add_or_set!(aff.terms, var, coef * term_coef)
    end
    aff.constant += coef * other.constant
    return aff
end

# Determine which variables are present in a function
_all_function_variables(f::GeneralVariableRef) = [f]
_all_function_variables(f::JuMP.GenericAffExpr) = [vref for vref in keys(f.terms)]
function _all_function_variables(f::JuMP.GenericQuadExpr)
    aff_vrefs = _all_function_variables(f.aff)
    vref_pairs = [k for k in keys(f.terms)]
    a_vrefs = [pair.a for pair in vref_pairs]
    b_vrefs = [pair.b for pair in vref_pairs]
    return unique([aff_vrefs; a_vrefs; b_vrefs])
end

# delete variables from an expression
function _remove_variable(f::JuMP.GenericAffExpr, vref::GeneralVariableRef)
    if haskey(f.terms, vref)
        delete!(f.terms, vref)
    end
    return
end
function _remove_variable(f::JuMP.GenericQuadExpr, vref::GeneralVariableRef)
    _remove_variable(f.aff, vref)
    vref_pairs = [k for k in keys(f.terms)]
    for i = 1:length(vref_pairs)
        if vref_pairs[i].a == vref
            delete!(f.terms, vref_pairs[i])
        elseif vref_pairs[i].b == vref
            delete!(f.terms, vref_pairs[i])
        end
    end
    return
end

# Check expression for a particular variable type via a recursive search
function _has_variable(vrefs::Vector{<:GeneralVariableRef}, vref::GeneralVariableRef; prior=[])
    if vrefs[1] == vref
        return true
    elseif isa(vrefs[1], MeasureRef)
        if length(vrefs) > 1
            _has_variable(_all_function_variables(measure_function(vrefs[1])), vref, prior = GeneralVariableRef[prior; vrefs[2:end]])
        else
            _has_variable(_all_function_variables(measure_function(vrefs[1])), vref, prior = prior)
        end
    elseif length(vrefs) > 1
        return _has_variable(vrefs[2:end], vref, prior = prior)
    elseif length(prior) > 0
        return _has_variable(prior, vref)
    else
        return false
    end
end
