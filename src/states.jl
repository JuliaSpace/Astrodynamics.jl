using ERFA
using Compat

import Base: convert, isapprox, ==

export State
export Frame, IAU
export ECI, ECEF, SEZ
export GCRF, CIRF, TIRF, ITRF

export rotation_matrix, body, rv_array, epoch, reference_frame, keplerian

abstract Frame

abstract GCRF <: Frame
abstract CIRF <: GCRF
abstract TIRF <: CIRF
abstract ITRF <: TIRF

abstract ECI <: GCRF
abstract ECEF <: ECI
abstract SEZ <: ECI

abstract IAU{C<:CelestialBody} <: GCRF

abstract AbstractState

immutable State{F<:Frame, T<:Timescale, C<:CelestialBody} <: AbstractState
    epoch::Epoch{T}
    rv::Vector{Float64}
    frame::Type{F}
    body::Type{C}
end

function State{F<:Frame, T<:Timescale, C<:CelestialBody}(ep::Epoch{T}, rv, frame::Type{F}=GCRF, body::Type{C}=Earth)
    State(ep, rv, frame, body)
end

function (==){F<:Frame, T<:Timescale, C<:CelestialBody}(a::State{F,T,C}, b::State{F,T,C})
    return a.epoch == b.epoch && a.rv == b.rv && a.frame == b.frame && a.body == a.body
end

function isapprox{F<:Frame, T<:Timescale, C<:CelestialBody}(a::State{F,T,C}, b::State{F,T,C})
    return a.epoch ≈ b.epoch && a.rv ≈ b.rv && a.frame == b.frame && a.body == a.body
end

body(s::State) = constants(s.body)
rv_array(s::State) = s.rv
epoch(s::State) = s.epoch
reference_frame(s::State) = s.frame

keplerian(s::State) = keplerian(rv_array(s), μ(body(s)))

function State{F1<:Frame, F2<:Frame, T1<:Timescale, T2<:Timescale, C1<:CelestialBody, C2<:CelestialBody}(
    s::State{F1, T1, C1}; frame::Type{F2}=s.frame, timescale::Type{T2}=s.epoch.scale, body::Type{C2}=s.body)
    convert(State{F2, T2, C2}, s)
end

convert{F<:Frame, T<:Timescale, C<:CelestialBody}(::Type{State{F, T, C}}, s::State{F, T, C}) = s

# F1 -> F2
function convert{F1<:Frame, F2<:Frame, T<:Timescale, C<:CelestialBody}(::Type{State{F2, T, C}}, s::State{F1, T, C})
    M = rotation_matrix(F2, F1, TDBEpoch(s.epoch))
    State(s.epoch, M * s.rv, F2, s.body)
end

# T1 -> T2
function convert{F<:Frame, T1<:Timescale, T2<:Timescale, C<:CelestialBody}(::Type{State{F, T2, C}}, s::State{F, T1, C})
    State(Epoch(T2, s.epoch), s.rv, F2, s.body)
end

# C1 -> C2
function convert{F<:Frame, T<:Timescale, C1<:CelestialBody, C2<:CelestialBody}(::Type{State{F, T, C2}}, s::State{F, T, C1})
    tdb = TDBEpoch(s.epoch)
    gcrf1 = State(s, frame=GCRF)
    body1 = state(C1, tdb)
    body2 = state(C2, tdb)
    gcrf2 = State(s.epoch, s.rv + body1 - body2, GCRF, C2)
    State(gcrf2, frame=F)
end

# F1 -> F2, T1 -> T2
function convert{F1<:Frame, F2<:Frame, T1<:Timescale, T2<:Timescale, C<:CelestialBody}(::Type{State{F2, T2, C}}, s::State{F1, T1, C})
    M = rotation_matrix(F2, F1, TDBEpoch(s.epoch))
    State(Epoch(T2, s.epoch), M * s.rv, F2, s.body)
end

# F1 -> F2, C1 -> C2
function convert{F1<:Frame, F2<:Frame, T<:Timescale, C1<:CelestialBody, C2<:CelestialBody}(::Type{State{F2, T, C2}}, s::State{F1, T, C1})
    tdb = TDBEpoch(s.epoch)
    gcrf1 = State(s, frame=GCRF)
    body1 = state(C1, tdb)
    body2 = state(C2, tdb)
    gcrf2 = State(s.epoch, s.rv + body1 - body2, GCRF, C2)
    State(gcrf2, frame=F2)
end

# T1 -> T2, C1 -> C2
function convert{F<:Frame, T1<:Timescale, T2<:Timescale, C1<:CelestialBody, C2<:CelestialBody}(::Type{State{F, T2, C2}}, s::State{F, T1, C1})
    tdb = TDBEpoch(s.epoch)
    gcrf1 = State(s, frame=GCRF)
    body1 = state(C1, tdb)
    body2 = state(C2, tdb)
    gcrf2 = State(s.epoch, s.rv + body1 - body2, GCRF, C2)
    State(gcrf2, timescale=T2)
end

# F1 -> F2, T1 -> T2, C1 -> C2
function convert{F1<:Frame, F2<:Frame, T1<:Timescale, T2<:Timescale, C1<:CelestialBody, C2<:CelestialBody}(::Type{State{F2,T2,C2}}, s::State{F1,T1,C1})
    tdb = TDBEpoch(s.epoch)
    gcrf1 = State(s, frame=GCRF)
    body1 = state(C1, tdb)
    body2 = state(C2, tdb)
    gcrf2 = State(s.epoch, s.rv + body1 - body2, GCRF, C2)
    State(gcrf2, frame=F2, timescale=T2)
end

# GCRF -> IAU
rotation_matrix{C<:CelestialBody}(::Type{IAU{C}}, ::Type{GCRF}, ep::Epoch) = rotation_matrix(C, ep)
# IAU -> GCRF
rotation_matrix{C<:CelestialBody}(::Type{GCRF}, ::Type{IAU{C}}, ep::Epoch) = rotation_matrix(C, ep)'
rotation_matrix{T<:Planet}(p::Type{T}, ep::Epoch) = rotation_matrix(constants(p), ep)

function rotation_matrix(p::Planet, ep::Epoch)
    α = right_ascension(p, ep)
    δα = right_ascension_rate(p, ep)
    δ = declination(p, ep)
    δδ = declination_rate(p, ep)
    ω = rotation_angle(p, ep)
    δω = rotation_rate(p, ep)
    ϕ = α + π/2
    χ = π/2 - δ

    M = zeros(6, 6)
    m = rotation_matrix(313, ϕ, χ, ω)
    δm = rate_matrix(313, ϕ, δα, χ, -δδ, ω, δω)
    M[1:3,1:3] = m
    M[4:6,4:6] = m
    M[4:6,1:3] = δm
    return M
end
