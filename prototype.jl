using ModelingToolkit
using NetworkDynamics
using Latexify
using OrdinaryDiffEq
using Plots

# https://github.com/SciML/ModelingToolkit.jl/issues/362
# https://github.com/SciML/ModelingToolkit.jl/issues/340

################# formulation with currents #################

@parameters t σ ρ β
@variables v(t) φ(t) ω(t) i_r(t) i_i(t)
@derivatives D'~t

third_order = [
            D(v) ~ σ - v - i_i,
            D(φ) ~ ω,
            D(ω) ~ β - ρ * ω - v * (cos(φ) * i_r + sin(φ) * i_i)
            ]

@parameters t G B
@variables vl(t) φl(t) vr(t) φr(t) i_r(t) i_i(t)
@derivatives D'~t

line_current = [
      D(i_r) ~ - i_r + G * (vl * cos(φl) - vr * cos(φr)) - B * (vl * sin(φl) - vr * sin(φr)),
      D(i_i) ~ - i_i + B * (vl * cos(φl) - vr * cos(φr)) + G * (vl * sin(φl) - vr * sin(φr)),
      ]

# components
node1 = ODESystem(third_order, t, [v, φ, ω, i_r, i_i], [σ, ρ, β]; name=:node1) 
node2 = ODESystem(third_order, t, [v, φ, ω, i_r, i_i], [σ, ρ, β]; name=:node2) 
line1 = ODESystem(line_current, t, [i_r, i_i, vr, φr, vl, φl], [G, B]; name=:line1) 

flow_constraints = [
      0 ~ node1.v - line1.vl,
      0 ~ node1.φ - line1.φl,
      0 ~ node2.v - line1.vr,
      0 ~ node2.φ - line1.φr,
      0 ~ node1.i_r - line1.i_r,
      0 ~ node1.i_i - line1.i_i,
      0 ~ node2.i_r + line1.i_r,
      0 ~ node2.i_i + line1.i_i,
]

network =  ODESystem(flow_constraints, t, [], [], systems=[node1, node2, line1])

p = [
      node1.σ => 1.0,
      node1.β => 1.0,
      node1.ρ => 1.0,
      node2.σ => 1.0,
      node2.β => -1.0,
      node2.ρ => 1.0,
      line1.G => 0.0,
      line1.B => 8.0,
      ]

# specifying valid initial conditioins this way is difficult ...
# need the alias eqns for this?
u0 = [
      node1.v => 1.0,
      node1.φ => 0.0,
      node1.ω => 0.0,
      node1.i_r => 0.0,
      node1.i_i => 0.0,
      node2.v => 1.0,
      node2.φ => 0.0,
      node2.ω => 0.0,
      node2.i_r => 0.0,
      node2.i_i => 0.0,
      line1.i_r => 0.5,
      line1.i_i => 0.5,
      line1.vl => 1.0,
      line1.φl => 0.0,
      line1.vr => 1.0,
      line1.φr => 0.0,
      ]

tspan = (0., 20.)

ode = ODEProblem(network, u0, tspan, p; jac=true, sparse=true)

sol = solve(ode, Rodas4());

plot(sol, vars=[node1.ω, node2.ω])

plot(sol, vars=[node1.v, node2.v])

plot(sol, vars=[node1.i_r, node2.i_r, line1.i_r])

# Now, I would like to add a droop control to node1.ω

@variables y(t)
controller = [D(y) ~ - node1.ρ * y, 0 ~ node1.ω - y]
ODESystem(controller,  t, [], [], systems=[network])

# This is probably not the way to go. A possibility would be to 
# directly modify the equations passed to node1 and create a new network.

################# formulation with power flow #################

@parameters t σ ρ β
@variables v(t) φ(t) ω(t) p(t) q(t)
@derivatives D'~t

third_order = [
            D(v) ~ σ - v - q / v,
            D(φ) ~ ω,
            D(ω) ~ β - ρ * ω - p
            ]

# components
node1 = ODESystem(third_order, t, [v, φ, ω, p, q], [σ, ρ, β]; name=:node1) 
node2 = ODESystem(third_order, t, [v, φ, ω, p, q], [σ, ρ, β]; name=:node2) 
      
@parameters G B

real_power(v_1, v_2, φ_1, φ_2, G, B) = G * v_1^2 - G * v_1 * v_2 * cos(φ_1 - φ_2) - B * v_1 * v_2 * sin(φ_1 - φ_2)
reactive_power(v_1, v_2, φ_1, φ_2, G, B) = -B * v_1^2 - G * v_1 * v_2 * sin(φ_1 - φ_2) + B * v_1 * v_2 * cos(φ_1 - φ_2)

flow_constraints = [
      0 ~ node1.p + real_power(node1.v, node2.v, node1.φ, node2.φ, G, B),
      0 ~ node2.p + real_power(node2.v, node1.v, node2.φ, node1.φ, G, B),
      0 ~ node1.q + reactive_power(node1.v, node2.v, node1.φ, node2.φ, G, B),
      0 ~ node2.q + reactive_power(node2.v, node1.v, node2.φ, node1.φ, G, B),
]

network =  ODESystem(flow_constraints, t, [], [G, B], systems=[node1, node2])

p = [
      node1.σ => 1.0,
      node1.β => 1.0,
      node1.ρ => 1.0,
      node2.σ => 1.0,
      node2.β => -1.0,
      node2.ρ => 1.0,
      G => 0.0,
      B => 8.0,
      ]

u0 = [
      node1.v => 1.0,
      node1.φ => 0.0,
      node1.ω => 0.0,
      node1.p => 0.0,
      node1.q => 0.0,
      node2.v => 1.0,
      node2.φ => 0.0,
      node2.ω => 0.0,
      node2.p => 0.0,
      node2.q => 0.0,
      ]

tspan = (0., 20.)

ode = ODEProblem(network, u0, tspan, p; jac=true, sparse=true)

sol = solve(ode, Rodas4());

plot(sol, vars=[node1.ω, node2.ω])

plot(sol, vars=[node1.v, node2.v])

plot(sol, vars=[node1.q, node1.q])