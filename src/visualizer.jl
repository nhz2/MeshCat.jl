function find_open_port(host, default_port, max_retries)
    for port in default_port:(default_port + max_retries)
        server = try
            listen(host, port)
        catch e
            if e isa Base.IOError
                continue
            end
        end
        close(server)
        # It is *possible* that a race condition could occur here, in which
        # some other process grabs the given port in between the close() above
        # and the open() below. But it's unlikely and would not be terribly
        # damaging (the user would just have to call open() again).
        return port
    end
end

function start_server(core::CoreVisualizer)
    router = HTTP.Router()
    HTTP.register!(router, "GET", "/main.min.js",
                    req -> HTTP.Response(200, MAIN_JS_STRING))
    HTTP.register!(router, "GET", "/index.html",
                    req -> HTTP.Response(200, INDEX_HTML_STRING))
    HTTP.register!(router, "GET", "/",
                   req -> HTTP.Response(200, INDEX_HTML_STRING))

    server = HTTP.listen!(core.host, core.port) do http
        if HTTP.WebSockets.isupgrade(http.message)
            HTTP.WebSockets.upgrade(http) do websocket
                push!(core.connections, websocket)
                send_scene(core.tree, websocket)
                wait()
            end
        else
            HTTP.streamhandler(router)(http)
        end
    end
    @info "MeshCat server started. You can open the visualizer by visiting the following URL in your browser:\n$(url(core))"
    return server
end

function close_server!(core::CoreVisualizer)
    if !isnothing(core.server) && isopen(core.server)
        HTTP.close(core.server)
        @info "MeshCat server closed."
    end
end

function url(core::CoreVisualizer)
    "http://$(core.host):$(core.port[])"
end

function update_tree!(core::CoreVisualizer, cmd::SetObject, data)
    core.tree[cmd.path].object = data
end

function update_tree!(core::CoreVisualizer, cmd::SetTransform, data)
    core.tree[cmd.path].transform = data
end

function update_tree!(core::CoreVisualizer, cmd::SetProperty, data)
    core.tree[cmd.path].properties[cmd.property] = data
end

function update_tree!(core::CoreVisualizer, cmd::Delete, data)
    if length(cmd.path) == 0
        core.tree = SceneNode()
    else
        delete!(core.tree, cmd.path)
    end
end

function update_tree!(core::CoreVisualizer, cmd::SetAnimation, data)
    core.tree.animation = data
end

function update_tree!(core::CoreVisualizer, cmd::SaveImage, data)
    nothing
end

function send_scene(tree::SceneNode, connection)
    foreach(tree) do node
        if node.object !== nothing
            HTTP.WebSockets.send(connection, node.object)
        end
        if node.transform !== nothing
            HTTP.WebSockets.send(connection, node.transform)
        end
        for data in values(node.properties)
            HTTP.WebSockets.send(connection, data)
        end
        if node.animation !== nothing
            HTTP.WebSockets.send(connection, node.animation)
        end
    end
end

function disconnect!(core::CoreVisualizer, websocket::HTTP.WebSockets.WebSocket)
    delete!(core.connections, websocket)
end


function Base.write(core::CoreVisualizer, data)
    for websocket in core.connections
        if HTTP.WebSockets.isclosed(websocket)
            disconnect!(core, websocket)
        else
            try
                HTTP.WebSockets.send(websocket, data)
            catch e
                if isa(e, Base.IOError)
                    disconnect!(core, websocket)
                else
                    rethrow(e)
                end
            end
        end
    end
end

function send(core::CoreVisualizer, cmd::AbstractCommand)
    data = pack(lower(cmd))
    update_tree!(core, cmd, data)
    write(core, data)

    nothing
end

function Base.wait(core::CoreVisualizer)
    while isempty(core.connections)
        sleep(0.5)
    end
end

"""
    vis = Visualizer()

Construct a new MeshCat visualizer instance.

Useful methods:

    vis[:group1] # get a new visualizer representing a sub-tree of the scene
    setobject!(vis, geometry) # set the object shown by this visualizer's sub-tree of the scene
    settransform!(vis, tform) # set the transformation of this visualizer's sub-tree of the scene
    setvisible!(vis, false) # hide this part of the scene
"""
struct Visualizer <: AbstractVisualizer
    core::CoreVisualizer
    path::Path
end

Visualizer() = Visualizer(CoreVisualizer(), ["meshcat"])

"""
$(TYPEDSIGNATURES)

Wait until at least one browser has connected to the
visualizer's server. This is useful in scripts to delay
execution until the browser window has opened.
"""
Base.wait(v::Visualizer) = wait(v.core)

# IJuliaCell(vis::Visualizer; kw...) = iframe(vis.core; kw...)

Base.show(io::IO, v::Visualizer) = print(io, "MeshCat Visualizer with path $(v.path) at $(url(v.core))")

"""
Set the object at this visualizer's path. This replaces whatever
geometry was presently at that path.

$(TYPEDSIGNATURES)

To draw multiple geometries, place them at different paths by using the slicing notation:

    setobject!(vis[:group1][:box1], geometry1)
    setobject!(vis[:group1][:box2], geometry2)
"""
function setobject!(vis::Visualizer, obj::AbstractObject)
    send(vis.core, SetObject(obj, vis.path))
    vis
end

"""
Set the transform of this visualizer's path. This can be done before or after
adding an object at that path.

$(TYPEDSIGNATURES)

The overall transform of an object is the composition of the transforms of all
of its parents, so setting the transform of `vis[:group1]` affects the poses of
the objects at `vis[:group1][:box1]` and `vis[:group1][:box2]`.
"""
function settransform!(vis::Visualizer, tform::Transformation)
    if !isempty(vis.core.animation_contexts)
        ctx = last(vis.core.animation_contexts)
        clip = getclip!(ctx.animation, vis.path)
        _setprop!(clip, ctx.frame, "scale", "vector3", js_scaling(tform))
        _setprop!(clip, ctx.frame, "position", "vector3", js_position(tform))
        _setprop!(clip, ctx.frame, "quaternion", "quaternion", js_quaternion(tform))
    else
        send(vis.core, SetTransform(tform, vis.path))
    end
    vis
end

"""
Delete the geometry at this visualizer's path and all of its descendants.

$(TYPEDSIGNATURES)
"""
function delete!(vis::Visualizer)
    send(vis.core, Delete(vis.path))
    vis
end

"""
Set a single property for the object at the given path.

$(TYPEDSIGNATURES)

(this is named setprop! instead of setproperty! to avoid confusion
with the Base.setproperty! function introduced in Julia v0.7)
"""
function setprop!(vis::Visualizer, property::AbstractString, value)
    if !isempty(vis.core.animation_contexts)
        ctx = last(vis.core.animation_contexts)
        clip = getclip!(ctx.animation, vis.path)
        _setprop!(clip, ctx.frame, property, get_property_type(property), value)
    else
        send(vis.core, SetProperty(vis.path, property, value))
    end
    vis
end

"""
Variation of `setprop!` which accepts an explicit type for the underlying JS property. This property type is only used within an animation context.

$(TYPEDSIGNATURES)
"""
function setprop!(vis::Visualizer, property::AbstractString, jstype::AbstractString, value)
    if !isempty(vis.core.animation_contexts)
        ctx = last(vis.core.animation_contexts)
        clip = getclip!(ctx.animation, vis.path)
        _setprop!(clip, ctx.frame, property, jstype, value)
    else
        send(vis.core, SetProperty(vis.path, property, value))
    end
    vis
end

"""
Set the currently playing animation in the visualizer.

$(TYPEDSIGNATURES)

"""
function setanimation!(vis::Visualizer, anim::Animation; play::Bool=true, repetitions::Integer=1)
    cmd = SetAnimation(anim, play, repetitions)
    send(vis.core, cmd)
end

"""
Takes a screenshot of the current visualizer and saves it as an image to the disk.

$(TYPEDSIGNATURES)
"""
function save_image(vis::Visualizer)
    send(vis.core, SaveImage())
    vis
end

"""
Get a new `Visualizer` representing a sub-tree of the same scene.

$(TYPEDSIGNATURES)

For example, if you have `vis::Visualizer` with path `/meshcat/foo`, you can do
`vis[:bar]` to get a new `Visualizer` with path `/meshcat/foo/bar`.
"""
Base.getindex(vis::Visualizer, path...) =
    Visualizer(vis.core, joinpath(vis.path, path...))

Animation(vis::Visualizer, args...; kw...) = Animation(vis.core, args...; kw...)
