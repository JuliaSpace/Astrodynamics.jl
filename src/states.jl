using ERFA
using Compat

import Base: convert, isapprox, ==, show

export State
export Frame, IAU
export GCRF, CIRF, TIRF, ITRF

export rotation_matrix, body, rv_array, epoch, reference_frame, keplerian

abstract Frame

abstract GCRF <: Frame
abstract CIRF <: GCRF
abstract TIRF <: CIRF
abstract ITRF <: TIRF

abstract IAU{C<:CelestialBody} <: GCRF

const FRAMES = (
    "GCRF",
    "CIRF",
    "TIRF",
    "ITRF",
)

for frame in FRAMES
    sym = symbol(frame)
    @eval begin
        show(io::IO, ::Type{$sym}) = print(io, $frame)
    end
end
show{C<:CelestialBody}(io::IO, ::Type{IAU{C}}) = print(io, "IAU{$C}")

abstract AbstractState

immutable State{F<:Frame, T<:Timescale, C<:CelestialBody} <: AbstractState
    epoch::Epoch{T}
    rv::Vector{Float64}
    frame::Type{F}
    body::Type{C}
end

function show(io::IO, s::State)
    println(io, "State{$(s.frame),$(s.epoch.scale),$(s.body)}:")
    println(io, " Epoch: $(s.epoch)")
    println(io, " Frame: $(s.frame)")
    println(io, " Body:  $(s.body)")
    println(io, " x: $(s.rv[1])")
    println(io, " y: $(s.rv[2])")
    println(io, " z: $(s.rv[3])")
    println(io, " u: $(s.rv[4])")
    println(io, " v: $(s.rv[5])")
    print(io, " w: $(s.rv[6])")
end

function State{F<:Frame, T<:Timescale, C<:CelestialBody}(ep::Epoch{T}, rv, frame::Type{F}=GCRF, body::Type{C}=Earth)
    State(ep, rv, frame, body)
end

function State{F<:Frame, T<:Timescale, C<:CelestialBody}(ep::Epoch{T}, r, v, frame::Type{F}=GCRF, body::Type{C}=Earth)
    State(ep, [r; v], frame, body)
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
    State(Epoch(T2, s.epoch), s.rv, F, s.body)
end

# C1 -> C2
function convert{F<:Frame, T<:Timescale, C1<:CelestialBody, C2<:CelestialBody}(::Type{State{F, T, C2}}, s::State{F, T, C1})
    M = rotation_matrix(F, GCRF, s.epoch)
    body1 = state(C1, s.epoch)
    body2 = state(C2, s.epoch)
    State(s.epoch, s.rv + M*body1 - M*body2, F, C2)
end

# F1 -> F2, T1 -> T2
function convert{F1<:Frame, F2<:Frame, T1<:Timescale, T2<:Timescale, C<:CelestialBody}(::Type{State{F2, T2, C}}, s::State{F1, T1, C})
    M = rotation_matrix(F2, F1, s.epoch)
    State(Epoch(T2, s.epoch), M * s.rv, F2, s.body)
end

# F1 -> F2, C1 -> C2
function convert{F1<:Frame, F2<:Frame, T<:Timescale, C1<:CelestialBody, C2<:CelestialBody}(::Type{State{F2, T, C2}}, s::State{F1, T, C1})
    M1 = rotation_matrix(F2, F1, s.epoch)
    M2 = rotation_matrix(F2, GCRF, s.epoch)
    body1 = state(C1, s.epoch)
    body2 = state(C2, s.epoch)
    State(s.epoch, M1*s.rv + M2*body1 - M2*body2, F2, C2)
end

# T1 -> T2, C1 -> C2
function convert{F<:Frame, T1<:Timescale, T2<:Timescale, C1<:CelestialBody, C2<:CelestialBody}(::Type{State{F, T2, C2}}, s::State{F, T1, C1})
    M = rotation_matrix(F, GCRF, s.epoch)
    body1 = state(C1, s.epoch)
    body2 = state(C2, s.epoch)
    State(Epoch(T2, s.epoch), s.rv + M*body1 - M*body2, F, C2)
end

# F1 -> F2, T1 -> T2, C1 -> C2
function convert{F1<:Frame, F2<:Frame, T1<:Timescale, T2<:Timescale, C1<:CelestialBody, C2<:CelestialBody}(::Type{State{F2,T2,C2}}, s::State{F1,T1,C1})
    M1 = rotation_matrix(F2, F1, s.epoch)
    M2 = rotation_matrix(F2, GCRF, s.epoch)
    body1 = state(C1, s.epoch)
    body2 = state(C2, s.epoch)
    State(Epoch(T2, s.epoch), M1*s.rv + M2*body1 - M2*body1, F2, C2)
end

rotation_matrix{F<:Frame}(::Type{F}, ::Type{F}, ep::Epoch) = eye(6, 6)

# GCRF -> IAU
function rotation_matrix{C<:CelestialBody}(::Type{IAU{C}}, ::Type{GCRF}, ep::Epoch)
    m, δm = rotation_matrix(C, TDBEpoch(ep))
    M = zeros(6, 6)
    M[1:3,1:3] = m
    M[4:6,4:6] = m
    M[4:6,1:3] = δm
    return M
end

# IAU -> GCRF
function rotation_matrix{C<:CelestialBody}(::Type{GCRF}, ::Type{IAU{C}}, ep::Epoch)
    m, δm = rotation_matrix(C, TDBEpoch(ep))
    M = zeros(6, 6)
    M[1:3,1:3] = m'
    M[4:6,4:6] = m'
    M[4:6,1:3] = δm'
    return M
end

rotation_matrix{T<:Planet}(p::Type{T}, ep::TDBEpoch) = rotation_matrix(constants(p), ep)

function rotation_matrix(p::Planet, ep::TDBEpoch)
    α = right_ascension(p, ep)
    δα = right_ascension_rate(p, ep)
    δ = declination(p, ep)
    δδ = declination_rate(p, ep)
    ω = rotation_angle(p, ep)
    δω = rotation_rate(p, ep)
    ϕ = α + π/2
    χ = π/2 - δ

    m = rotation_matrix(313, ϕ, χ, ω)
    δm = rate_matrix(313, ϕ, δα, χ, -δδ, ω, δω)
    return m, δm
end

function rotation_matrix(::Type{CIRF}, ::Type{GCRF}, ep::Epoch)
    m = rotation_matrix(DATA.iau2000, TTEpoch(ep))
    M = zeros(6,6)
    M[1:3,1:3] = m'
    M[4:6,4:6] = m'
    return M
end

function rotation_matrix(::Type{GCRF}, ::Type{CIRF}, ep::Epoch)
    m = rotation_matrix(DATA.iau2000, TTEpoch(ep))
    M = zeros(6,6)
    M[1:3,1:3] = m
    M[4:6,4:6] = m
    return M
end

function rotation_matrix(data::IAU2000, ep::TTEpoch)
    dx, dy = interpolate(data, ep)
    x, y = eraXy06(ep.jd, ep.jd1)
    s = eraS06(ep.jd, ep.jd1, x, y)
    x += dx
    y += dy
    reshape(eraC2ixys(x, y, s), (3,3))
end

function rotation_matrix(::Type{TIRF}, ::Type{CIRF}, ep::Epoch)
    ut1 = UT1Epoch(ep)
    era = eraEra00(ut1.jd, ut1.jd1)
    rate = rotation_rate(EARTH, TDBEpoch(ep))
    m = rotation_matrix(3, era)
    M = zeros(6,6)
    M[1:3,1:3] = m
    M[4:6,4:6] = m
    M[4:6,1:3] = rate_matrix(3, era, rate)
    return M
end

function rotation_matrix(::Type{CIRF}, ::Type{TIRF}, ep::Epoch)
    ut1 = UT1Epoch(ep)
    era = eraEra00(ut1.jd, ut1.jd1)
    rate = rotation_rate(EARTH, TDBEpoch(ep))
    m = rotation_matrix(3, -era)
    M = zeros(6,6)
    M[1:3,1:3] = m
    M[4:6,4:6] = m
    M[4:6,1:3] = rate_matrix(3, -era, -rate)
    return M
end

function rotation_matrix(data::PolarMotion, ep::TTEpoch)
    xp, yp = interpolate(data, ep)
    reshape(eraPom00(xp, yp, eraSp00(ep.jd, ep.jd1)), (3,3))
end

function rotation_matrix(::Type{ITRF}, ::Type{TIRF}, ep::Epoch)
    m = rotation_matrix(DATA.polarmotion, TTEpoch(ep))
    M = zeros(6,6)
    M[1:3,1:3] = m'
    M[4:6,4:6] = m'
    return M
end

function rotation_matrix(::Type{TIRF}, ::Type{ITRF}, ep::Epoch)
    m = rotation_matrix(DATA.polarmotion, TTEpoch(ep))
    M = zeros(6,6)
    M[1:3,1:3] = m
    M[4:6,4:6] = m
    return M
end

@generated function rotation_matrix{F1<:Frame, F2<:Frame}(::Type{F2}, ::Type{F1}, ep::Epoch)
    rotation_matrix_generator(F2, F1, ep)
end

function rotation_matrix_generator(F2, F1, ep)
    path = findpath(F1, F2, Frame)
    if length(path) == 2
        error("Please provide a method rotation_matrix(::Type{$F2}, ::Type{$F1}, ::Epoch).")
    end
    ex = :(rotation_matrix($(path[2]), $(path[1]), ep))
    for (origin, target) in zip(path[2:end], path[3:end])
        ex = :(rotation_matrix($target, $origin, ep)*$ex)
    end
    return ex
end
