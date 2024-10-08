struct PlotGrid{G<:Grid}
    grid::G
end

Gridap.Geometry.get_grid(pg::PlotGrid) = pg.grid

setup_color(color::Union{Symbol, Makie.Colorant}, ::Grid) = color

function setup_color(color::AbstractArray, grid::Grid)
    color = if length(color) == num_nodes(grid)
                to_dg_node_values(grid, color)
            elseif length(color) == num_cells(grid)
                to_dg_cell_values(grid, color)
            else
                @unreachable
            end
end

setup_face_color(color::Union{Symbol, Makie.Colorant}, ::Grid, ::Any) = color

function setup_face_color(color::AbstractArray, grid::Grid, face_to_cell)
    color = if length(color) == num_nodes(grid)
                color
            elseif length(color) == num_cells(grid)
                color[face_to_cell]
            else
                @unreachable
            end
end

mesh_theme = Makie.Theme(
        color      = :pink,
        colormap   = :bluesreds,
        shading    = Makie.NoShading,
        cycle      = nothing
)

# By merging the default theme for the Mesh type and some attributes whose values we want to impose from mesh_theme
# (in this case: color, colormap, etc.), we may override the current default theme and use our settings.
# Note: Makie.Theme() returns an Attributes type.
@Makie.recipe(PlotGridMesh) do scene
    merge!(
        mesh_theme,
        Makie.default_theme(scene, Makie.Mesh)
    )
end


# The lift function is necessary when dealing with reactive attributes or Observables.
#function Makie.plot!(plot::Makie.Mesh{<:Tuple{PlotGrid}})
function Makie.plot!(plot::PlotGridMesh{<:Tuple{PlotGrid}})
    grid = Makie.lift(get_grid, plot[1])
    D = num_cell_dims(grid[])
    if D in (0,1,2)
      color = Makie.lift(setup_color, plot[:color], grid)
      mesh = Makie.lift(to_plot_dg_mesh, grid)
    elseif D == 3
      face_grid_and_map = Makie.lift(to_face_grid_with_map, grid)
      face_grid = Makie.lift(first, face_grid_and_map)
      face_to_cell = Makie.lift(i->i[2], face_grid_and_map)
      face_color = Makie.lift(setup_face_color, plot[:color], grid, face_to_cell)
      mesh = Makie.lift(m->m|>to_plot_dg_mesh|>GeometryBasics.normal_mesh, face_grid)
      color = Makie.lift(setup_color, face_color, face_grid)
    else
      @unreachable
    end

    # plot.attributes.attributes returns a Dict{Symbol, Observable} to be called by any function.
    # plot.attributes returns an Attributes type.
    if D in (2,3)
        valid_attributes = Makie.shared_attributes(plot,Makie.Mesh)
        valid_attributes[:color] = color
        Makie.mesh!(plot, valid_attributes, mesh)
    elseif D == 1
        valid_attributes = Makie.shared_attributes(plot,Makie.LineSegments)
        valid_attributes[:color] = color
        Makie.linesegments!(plot, valid_attributes, mesh )
    elseif D == 0
        valid_attributes = Makie.shared_attributes(plot,Makie.Scatter)
        valid_attributes[:color] = color
        Makie.scatter!(plot, valid_attributes, mesh )
    else
        @unreachable
    end
end

# No need to create discontinuous meshes for wireframe and scatter.
function Makie.convert_arguments(::Type{<:Makie.Wireframe}, pg::PlotGrid)
    grid = get_grid(pg)
    mesh = to_plot_mesh(grid)
    (mesh, )
end

function Makie.convert_arguments(::Type{<:Makie.Scatter}, pg::PlotGrid)
    grid = get_grid(pg)
    node_coords = get_node_coordinates(grid)
    x = map(to_point, node_coords)
    (x, )
end

function Makie.convert_arguments(::Type{PlotGridMesh}, trian::Triangulation)
    grid = to_grid(trian)
    (PlotGrid(grid), )
end

function Makie.convert_arguments(t::Type{<:Union{Makie.Wireframe, Makie.Scatter}}, trian::Triangulation)
    grid = to_grid(trian)
    Makie.convert_arguments(t, PlotGrid(grid))
end

# Set default plottype as mesh if argument is type Triangulation, i.e., mesh(Ω) == plot(Ω).
Makie.plottype(::Triangulation{Dc,1}) where Dc = Makie.Scatter
Makie.plottype(::Triangulation{Dc,Dp}) where {Dc,Dp} = PlotGridMesh
Makie.args_preferred_axis(t::Triangulation)= num_point_dims(t)<=2 ? Makie.Axis : Makie.LScene
Makie.plottype(::PlotGrid) = PlotGridMesh
Makie.args_preferred_axis(pg::PlotGrid)= num_point_dims(pg.Grid)<=2 ? Makie.Axis : Makie.LScene

@Makie.recipe(MeshField) do scene
    merge!(
        mesh_theme,
        Makie.default_theme(scene, Makie.Mesh)
    )
end

# We explicitly set the colorrange property of p to (min, max) of the color provided. Here, when we use mesh(),
# Makie fills the attribute plots of p (p.plots) with the given attributes. Hence, p.plots[1] inherits the colorrange
# of p (this is just to draw colorbars). Another way would be using $ Colorbar(fig[1,2], plt.plots[1]), but quite less
# appealing from the point of view of the user.
function Makie.plot!(p::MeshField{<:Tuple{Triangulation, Any}})
    trian, uh = p[1:2]
    grid_and_data = Makie.lift(to_grid, trian, uh)
    pg = Makie.lift(i->PlotGrid(i[1]), grid_and_data)
    p[:color] = Makie.lift(i->i[2], grid_and_data)
    if p[:colorrange][] === Makie.automatic
        p[:colorrange] = Makie.lift(extrema, p[:color])
    end
    Makie.plot!(p, pg;
        p.attributes.attributes...
    )
end

Makie.plottype(::Triangulation{Dc,1}, ::Any) where Dc = Makie.Scatter
Makie.plottype(::Triangulation{Dc,Dp}, ::Any) where {Dc,Dp} = MeshField

function Makie.plot!(p::MeshField{<:Tuple{CellField}})
    uh = p[1]
    trian = Makie.lift(get_triangulation, uh)
    grid_and_data = Makie.lift(to_grid, trian, uh)
    pg = Makie.lift(i->PlotGrid(i[1]), grid_and_data)
    p[:color] = Makie.lift(i->i[2], grid_and_data)
    if p[:colorrange][] === Makie.automatic
        p[:colorrange] = Makie.lift(extrema, p[:color])
    end
    Makie.plot!(p, pg;
        p.attributes.attributes...
    )
end

function Makie.convert_arguments(::Union{Type{Makie.Lines},Type{Makie.ScatterLines},Type{Makie.Scatter}}, c::CellField)
    trian=get_triangulation(c)
    if num_point_dims(trian)==1
        return to_point1D(trian, c)
    else
        ArgumentError("This function requires a 1D CellField")
    end
end

function Makie.convert_arguments(::Union{Type{Makie.Lines},Type{Makie.ScatterLines},Type{Makie.Scatter}}, trian::Triangulation{Dc,1}, uh::Any=x->0.0) where Dc
    return to_point1D(trian, uh)
end

Makie.plottype(c::CellField) = Makie.plottype(get_triangulation(c),c)
Makie.args_preferred_axis(c::CellField)= Makie.args_preferred_axis(get_triangulation(c))

function Makie.point_iterator(pg::PlotGrid)
    UnstructuredGrid(pg.grid) |> to_dg_points
end
