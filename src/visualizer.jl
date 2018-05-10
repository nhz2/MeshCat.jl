mutable struct CoreVisualizer
    scope::WebIO.Scope
    tree::SceneNode
    command_channel::Observable{Vector{UInt8}}
    request_channel::Observable{String}
    controls_channel::Observable{Vector{Any}}
    controls::Dict{String, Tuple{Observable, AbstractControl}}

    function CoreVisualizer()
        scope = WebIO.Scope(
            imports=[
                "pkg/MeshCat/meshcat/dist/main.min.js"
            ]
        )
        command_channel = Observable(scope, "meshcat-command", UInt8[])
        request_channel = Observable(scope, "meshcat-request", "")
        controls_channel = Observable(scope, "meshcat-controls", [])
        viewer_name = "meshcat_viewer_$(scope.id)"

        onimport(scope, @js function(mc)
            @var element = this.dom.children[0];
            window[$viewer_name] = @new mc.Viewer(element)
            $request_channel[] = String(Date.now())
            window.document.body.style.margin = "0"
        end)

        onjs(command_channel, @js function(val)
            window[$viewer_name].handle_command_message(Dict(:data => val))
        end)
        scope = scope(dom"div.meshcat-viewer"(
            style=Dict(
                :width => "100vw",
                :height => "100vh",
                :position => "absolute",
                :left => 0,
                :right => 0,
                :margin => 0,
            )
        ))
        scope.dom.props[:style][:overflow] = "hidden"

        tree = SceneNode()
        controls = Dict{String, Observable}()
        vis = new(scope, tree, command_channel, request_channel, controls_channel, controls)
        on(request_channel) do x
            send_scene(vis)
        end

        on(controls_channel) do msg
            name::String, value = msg
            if haskey(vis.controls, name)
                @async vis.controls[name] = value
                # Base.invokelatest(setindex!, vis.controls[name], value)
            end
        end
        vis
    end
end

WebIO.render(core::CoreVisualizer) = core.scope

function WebIO.iframe(core::CoreVisualizer; height="100%", width="100%", minHeight="400px")
    ifr = WebIO.iframe(core.scope)
    onimport(ifr, @js function()
        this.dom.style.height = "100%"
    end)
    ifr.dom.props[:style]["height"] = height
    ifr.dom.props[:style]["minHeight"] = minHeight
    ifr.dom.props[:style]["width"] = width
    ifr.dom.props[:style]["display"] = "flex"
    ifr.dom.props[:style]["flexDirection"] = "column"
    ifr.dom.children[1].props[:style]["flexGrow"] = "1"
    ifr
end


function update_tree!(core::CoreVisualizer, cmd::SetObject, data)
    core.tree[cmd.path].object = data
end

function update_tree!(core::CoreVisualizer, cmd::SetTransform, data)
    core.tree[cmd.path].transform = data
end

function update_tree!(core::CoreVisualizer, cmd::Delete, data)
    if length(cmd.path) == 0
        core.tree = SceneNode()
    else
        delete!(core.tree, cmd.path)
    end
end

update_tree!(core::CoreVisualizer, cmd::SetControl, data) = nothing

function send_scene(core::CoreVisualizer)
    foreach(core.tree) do node
        if !isnull(node.object)
            core.command_channel[] = get(node.object)
        end
        if !isnull(node.transform)
            core.command_channel[] = get(node.transform)
        end
    end
    for (name, (obs, control)) in core.controls
        send(core, SetControl(control))
    end
end

function Base.send(c::CoreVisualizer, cmd::AbstractCommand)
    data = pack(lower(cmd))
    update_tree!(c, cmd, data)
    c.command_channel[] = data
    nothing
end

function Base.wait(c::CoreVisualizer)
    while isempty(c.scope.pool.connections)
        sleep(0.25)
    end
end

"""
    vis = Visualizer()

Construct a new MeshCat visualizer instance.

Useful methods:

    vis[:group1] # get a new visualizer representing a sub-tree of the scene
    setobject!(vis, geometry) # set the object shown by this visualizer's sub-tree of the scene
    settransform!(vis], tform) # set the transformation of this visualizer's sub-tree of the scene
"""
struct Visualizer
    core::CoreVisualizer
    path::Path
end

Visualizer() = Visualizer(CoreVisualizer(), ["meshcat"])

# """
# Open the visualizer's web URL in your default browser
# """
# Base.open(v::Visualizer) = (open(v.window); v)
# Base.close(v::Visualizer) = close(v.window)

"""
$(SIGNATURES)

Wait until at least one browser has connected to the
visualizer's server. This is useful in scripts to delay
execution until the browser window has opened.
"""
Base.wait(v::Visualizer) = wait(v.core)

IJuliaCell(vis::Visualizer; kw...) = iframe(vis.core; kw...)

Base.show(io::IO, v::Visualizer) = print(io, "MeshCat Visualizer with path $(v.path)")

"""
$(SIGNATURES)

Set the object at this visualizer's path. This replaces whatever
geometry was presently at that path. To draw multiple geometries,
place them at different paths by using the slicing notation:

    setobject!(vis[:group1][:box1], geometry1)
    setobject!(vis[:group1][:box2], geometry2)
"""
function setobject!(vis::Visualizer, obj::AbstractObject)
    send(vis.core, SetObject(obj, vis.path))
    vis
end

setobject!(vis::Visualizer, geom::GeometryLike) = setobject!(vis, Object(geom))
setobject!(vis::Visualizer, geom::GeometryLike, material::AbstractMaterial) = setobject!(vis, Object(geom, material))

"""
$(SIGNATURES)

Set the transform of this visualizer's path. This can be done
before or after adding an object at that path. The overall transform
of an object is the composition of the transforms of all of its parents,
so setting the transform of `vis[:group1]` affects the poses of the objects
at `vis[:group1][:box1]` and `vis[:group1][:box2]`.
"""
function settransform!(vis::Visualizer, tform::Transformation)
    send(vis.core, SetTransform(tform, vis.path))
    vis
end

"""
$(SIGNATURES)

Delete the geometry at this visualizer's path and all of its descendants.
"""
function delete!(vis::Visualizer)
    send(vis.core, Delete(vis.path))
    vis
end

function setcontrol!(vis::Visualizer, name::AbstractString, obs::Observable)
    control = Button(vis.core.controls_channel, name)
    vis.core.controls[name] = (obs, control)
    send(vis.core, SetControl(control))
    vis
end

function setcontrol!(vis::Visualizer, name::AbstractString, obs::Observable, value, min=zero(value), max=one(value))
    control = NumericControl(vis.core.controls_channel, name, value, min, max)
    vis.core.controls[name] = (obs, control)
    send(vis.core, SetControl(control))
    vis
end

Base.getindex(vis::Visualizer, path::Union{Symbol, AbstractString}...) = Visualizer(vis.core, vcat(vis.path, path...))
