using GLMakie, YAML, Colors

# Define data structures matching the YAML schema
struct Point
    x::Float64
    y::Float64
end

struct Point3D
    x::Float64
    y::Float64
    t::Float64
end

struct Reach
    exterior::Vector{Point}
    interiors::Vector{Vector{Point}}
end

struct Velocity
    x::Float64
    y::Float64
end

struct Position
    x::Float64
    y::Float64
end

struct Agent
    name::String
    reach::Reach
    position::Position
    velocity::Velocity
    safety_x::Float64
    order::Int
end

# Movement types enum
@enum MovementType Idle Scheduled Evasive

# Convert string to MovementType
function string_to_movement_type(s::String)
    if s == "Idle"
        return Idle
    elseif s == "Scheduled"
        return Scheduled
    elseif s == "Evasive"
        return Evasive
    else
        error("Unknown movement type: $s")
    end
end

struct MovementSegment
    points::Vector{Point3D}
    movement_type::MovementType
end

struct AgentTrajectory
    config::Agent
    segments::Vector{MovementSegment}
end

# Deserialization functions
function des_point(data::Dict)
    return Point(data["x"], data["y"])
end

function des_point3d(data::Dict)
    return Point3D(data["x"], data["y"], data["t"])
end

function des_reach(data::Dict)
    exterior = [des_point(p) for p in data["exterior"]]
    interiors = [des_point.(interior) for interior in data["interiors"]]
    return Reach(exterior, interiors)
end

function des_position(data::Dict)
    return Position(data["x"], data["y"])
end

function des_velocity(data::Dict)
    return Velocity(data["x"], data["y"])
end

function des_agent(data::Dict)
    return Agent(
        data["name"],
        des_reach(data["reach"]),
        des_position(data["position"]),
        des_velocity(data["velocity"]),
        data["safety_x"],
        data["order"]
    )
end

function des_movement_segment(segment_data::Vector)
    if length(segment_data) < 2
        error("Invalid segment data structure")
    end
    
    points_data = segment_data[1]
    movement_type = string_to_movement_type(segment_data[2])
    
    points = map(des_point3d, points_data)
    return MovementSegment(points, movement_type)
end

function deserialize_agent_trajectory(agent_data::Vector)
    if length(agent_data) < 2
        error("Invalid agent data structure")
    end
    
    agent = des_agent(agent_data[1])
    
    segments = MovementSegment[]
    trajectory_data = agent_data[2]
    segments = map(des_movement_segment, trajectory_data)

    return AgentTrajectory(agent, segments)
end

# Load and deserialize the YAML file
function load_agent_trajectories(filepath::String)
    raw_data = YAML.load_file(filepath)
    trajectories = AgentTrajectory[]
    
    for agent_data in raw_data
        try
            trajectory = deserialize_agent_trajectory(agent_data)
            push!(trajectories, trajectory)
        catch e
            println("Warning: Failed to parse agent: $e")
            continue
        end
    end
    
    return trajectories
end

# Extract trajectory data for visualization
function extract_plot_data(trajectories::Vector{AgentTrajectory})
    plot_data = []
    
    for trajectory in trajectories
        # Collect all points and their types
        all_points = Point3D[]
        point_types = MovementType[]
        segment_endpoints = Tuple{Point3D, MovementType}[]
        
        for segment in trajectory.segments
            for point in segment.points
                push!(all_points, point)
                push!(point_types, segment.movement_type)
            end
            
            # Mark the last point of each segment
            if !isempty(segment.points)
                push!(segment_endpoints, (segment.points[end], segment.movement_type))
            end
        end
        
        push!(plot_data, (
            name = trajectory.config.name,
            points = all_points,
            types = point_types,
            endpoints = segment_endpoints,
            config = trajectory.config
        ))
    end
    
    return plot_data
end

# Create the 3D plot
function plot_trajectories(trajectories::Vector{AgentTrajectory})
    plot_data = extract_plot_data(trajectories)
    
    fig = Figure(resolution = (1200, 800))
    ax = Axis3(fig[1, 1], 
              xlabel = "X Position", 
              ylabel = "Y Position", 
              zlabel = "Time",
              title = "Agent Trajectories in 3D (X, Y, Time)")
    
    # Colors for different agents
    agent_colors = [colorant"red", colorant"blue", colorant"green", colorant"orange", colorant"purple"]
    
    # Symbols for different movement types
    movement_symbols = Dict(
        Idle => :circle,
        Scheduled => :utriangle,
        Evasive => :diamond
    )
    
    for (i, data) in enumerate(plot_data)
        agent_color = agent_colors[mod1(i, length(agent_colors))]
        
        if !isempty(data.points)
            # Extract coordinates
            xs = [p.x for p in data.points]
            ys = [p.y for p in data.points]
            ts = [p.t for p in data.points]
            
            # Plot trajectory line
            lines!(ax, xs, ys, ts, 
                  color = agent_color, 
                  linewidth = 2,
                  label = data.name)
            
            # Plot endpoint markers for each movement segment
            for (endpoint, movement_type) in data.endpoints
                symbol = get(movement_symbols, movement_type, :circle)
                scatter!(ax, [endpoint.x], [endpoint.y], [endpoint.t],
                        color = agent_color,
                        marker = symbol,
                        markersize = 12,
                        strokewidth = 1,
                        strokecolor = :black)
            end
        end
    end
    
    # Create custom legend for movement types
    legend_elements = []
    movement_labels = []
    for (movement_type, symbol) in movement_symbols
        push!(legend_elements, MarkerElement(color = :black, marker = symbol, markersize = 12,
                                           strokewidth = 1, strokecolor = :black))
        push!(movement_labels, string(movement_type))
    end
    
    # Add legends
    Legend(fig[1, 2], 
           [LineElement(color = agent_colors[i], linewidth = 2) for i in 1:length(plot_data)],
           [data.name for data in plot_data],
           "Agents")
    
    Legend(fig[2, 1], 
           legend_elements,
           movement_labels,
           "Movement Types",
           orientation = :horizontal)
    
    # Invert Z-axis so time runs from top to bottom
    ax.zreversed = true
    
    return fig
end

# Plot t-x projection of the agent trajectories
function plot_tx_projection(trajectories::Vector{AgentTrajectory})
    plot_data = extract_plot_data(trajectories)
    
    fig = Figure(resolution = (1000, 600))
    ax = Axis(fig[1, 1],
              xlabel = "X Position",
              ylabel = "Time (t)",
              title = "Agent Trajectories: t-x Projection")
    
    agent_colors = [colorant"red", colorant"blue", colorant"green", colorant"orange", colorant"purple"]
    movement_symbols = Dict(
        Idle => :circle,
        Scheduled => :utriangle,
        Evasive => :diamond
    )
    
    for (i, data) in enumerate(plot_data)
        agent_color = agent_colors[mod1(i, length(agent_colors))]
        if !isempty(data.points)
            ts = [p.t for p in data.points]
            xs = [p.x for p in data.points]
            lines!(ax, xs, ts, color = agent_color, linewidth = 2, label = data.name)
            # Mark segment endpoints
            for (endpoint, movement_type) in data.endpoints
                symbol = get(movement_symbols, movement_type, :circle)
                scatter!(ax, [endpoint.x], [endpoint.t], 
                         color = agent_color,
                         marker = symbol,
                         markersize = 12,
                         strokewidth = 1,
                         strokecolor = :black)
            end
        end
    end
    
    # Custom legend for movement types
    legend_elements = []
    movement_labels = []
    for (movement_type, symbol) in movement_symbols
        push!(legend_elements, MarkerElement(color = :black, marker = symbol, markersize = 12,
                                             strokewidth = 1, strokecolor = :black))
        push!(movement_labels, string(movement_type))
    end
    
    Legend(fig[1, 2],
           [LineElement(color = agent_colors[i], linewidth = 2) for i in 1:length(plot_data)],
           [data.name for data in plot_data],
           "Agents")
    
    Legend(fig[2, 1],
           legend_elements,
           movement_labels,
           "Movement Types",
           orientation = :horizontal)
    
    ax.yreversed = true
    return fig
end

# Print trajectory summary
function print_trajectory_summary(trajectories::Vector{AgentTrajectory})
    println("Loaded $(length(trajectories)) agent trajectories:")
    for traj in trajectories
        total_points = sum(length(seg.points) for seg in traj.segments)
        println("  $(traj.config.name):")
        println("    - Total points: $total_points")
        println("    - Segments: $(length(traj.segments))")
        println("    - Position: ($(traj.config.position.x), $(traj.config.position.y))")
        println("    - Velocity: ($(traj.config.velocity.x), $(traj.config.velocity.y))")
        println("    - Safety margin: $(traj.config.safety_x)")
        
        # Count movement types
        movement_counts = Dict{MovementType, Int}()
        for seg in traj.segments
            movement_counts[seg.movement_type] = get(movement_counts, seg.movement_type, 0) + 1
        end
        
        println("    - Movement types: $movement_counts")
        println()
    end
end

# Main execution
function main()
    # Load the data (replace with your file path)
    filepath = "/home/hendrik/log/paths.yml"  # Update this path
    
    try
        trajectories = load_agent_trajectories(filepath)
        
        # Print summary
        print_trajectory_summary(trajectories)
        
        # Create and display the plot
        fig = plot_tx_projection(trajectories)
        display(fig)
        
    catch e
        println("Error loading or processing data: ", e)
        println("Make sure the YAML file path is correct and the file is properly formatted.")
        rethrow(e)
    end
end

# Run the visualization
main()