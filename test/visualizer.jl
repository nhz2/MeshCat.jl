using Electron: Application
import GeometryBasics

app = Application()
vis = Visualizer()

if !haskey(ENV, "CI")
    open(vis)
end

open(vis, app)

if !haskey(ENV, "CI")
    wait(vis)
end

# A custom geometry type to test that we can render arbitrary primitives
# by decomposing them into simple meshes. This replaces the previous test
# which did the same thing using a Polyhedron from Polyhedra.jl. The Polyhedra
# test was removed because it required too many external dependencies just to
# verify a simple interface.
struct CustomGeometry <: GeometryPrimitive{3, Float64}
end

# GeometryBasics.isdecomposable(::Type{<:Face}, ::CustomGeometry) = true
function GeometryBasics.decompose(::Type{F}, c::CustomGeometry) where {F <: NgonFace}
    [convert(F, NgonFace(1,2,3))]
end
# GeometryBasics.isdecomposable(::Type{<:Point}, ::CustomGeometry) = true
function GeometryBasics.decompose(::Type{P}, c::CustomGeometry) where {P <: Point}
    convert(Vector{P}, [Point(0., 0, 0), Point(0., 1, 0), Point(0., 0, 1)])
end

@testset "self-contained visualizer" begin
    cat_mesh_path = joinpath(@__DIR__, "data", "meshes", "cat.obj")

    @testset "shapes" begin
        v = vis[:shapes]
        delete!(v)
        settransform!(v, Translation(1., 0, 0))
        @testset "box" begin
            setobject!(v[:box], Rect(Vec(0., 0, 0), Vec(0.1, 0.2, 0.3)))
            settransform!(v[:box], Translation(-0.05, -0.1, 0))
        end

        @testset "cylinder" begin
            setobject!(v[:cylinder], MeshObject(
               Cylinder(Point(0., 0, 0), Point(0, 0, 0.2), 0.1),
               MeshLambertMaterial(color=colorant"lime")))
            settransform!(v[:cylinder], Translation(0, 0.5, 0.0))
        end

        @testset "sphere" begin
            setobject!(v[:sphere],
                HyperSphere(Point(0., 0, 0), 0.15),
                MeshLambertMaterial(color=colorant"maroon"))
            settransform!(v[:sphere], Translation(0, 1, 0.15))
        end

        @testset "ellipsoid" begin
            setobject!(v[:ellipsoid], HyperEllipsoid(Point(0., 1.5, 0), Vec(0.3, 0.1, 0.1)))
            settransform!(v[:ellipsoid], Translation(0, 0, 0.1))
        end

        @testset "cube" begin
            setobject!(v[:cube], Rect(Vec(-0.1, -0.1, 0), Vec(0.2, 0.2, 0.2)), MeshBasicMaterial())
            settransform!(v[:cube], Translation(0, 2.0, 0))
        end

        @testset "more complicated cylinder" begin
            setobject!(v[:cylinder2], Cylinder(Point(0, 2.5, 0), Point(0.1, 2.6, 0), 0.05))
            settransform!(v[:cylinder2], Translation(0, 0, 0.05))
        end

        @testset "triad" begin
            setobject!(v[:triad], Triad(0.2))
            settransform!(v[:triad], Translation(0, 3, 0.2))
        end

        @testset "cone" begin
            setobject!(v[:cone],
                Cone(Point(1., 1., 1.), Point(1., 1., 1.2), 0.1),
                MeshLambertMaterial(color=colorant"indianred"))
            settransform!(v[:cone], Translation(-1, 2.5, -1))
        end
    end

    @testset "meshes" begin
        v = vis[:meshes]
        @testset "cat" begin
            mesh = load(cat_mesh_path)
            setobject!(v[:cat], mesh)
            settransform!(v[:cat], Translation(0, -1, 0) ∘ LinearMap(RotZ(Float64(π))) ∘ LinearMap(RotX(π/2)))
        end

        @testset "cat_color" begin
            mesh = load(cat_mesh_path)
            color = RGBA{Float32}(0.5, 0.5, 0.5, 0.5)
            setobject!(v[:cat_color], mesh,
                       MeshLambertMaterial(color=color))
            settransform!(v[:cat_color], Translation(0, -2.0, 0) ∘ LinearMap(RotZ(Float64(π))) ∘ LinearMap(RotX(π/2)))
        end

        @testset "mesh file geometries" begin
            settransform!(v[:mesh_file_geometries], Translation(0, -3.0, 0))
            base_path = joinpath(@__DIR__, "data", "meshes", "mesh_0_convex_piece_0")
            @testset "obj" begin
                path = base_path * ".obj"
                setobject!(v[:mesh_file_geometries, :obj], MeshFileGeometry(path))
            end
            @testset "dae" begin
                path = base_path * ".dae"
                setobject!(v[:mesh_file_geometries, :dae], MeshFileGeometry(path))
                settransform!(v[:mesh_file_geometries, :dae], Translation(0, -0.5, 0))
            end
            @testset "stl_ascii" begin
                path = base_path * ".ascii.stl"
                setobject!(v[:mesh_file_geometries, :stl_ascii], MeshFileGeometry(path))
                settransform!(v[:mesh_file_geometries, :stl_ascii], Translation(0, -1.0, 0))
            end
            @testset "stl_binary" begin
                path = base_path * ".binary.stl"
                setobject!(v[:mesh_file_geometries, :stl_binary], MeshFileGeometry(path))
                settransform!(v[:mesh_file_geometries, :stl_binary], Translation(0, -1.5, 0))
            end
        end

        @testset "mesh file objects" begin
            let v = v[:mesh_file_objects]
                settransform!(v, Translation(0, 3.0, -1.5))

                base_path = joinpath(@__DIR__, "data", "meshes")
                @testset "obj" begin
                    path = joinpath(base_path, "cube.obj")
                    setobject!(v[:obj], MeshFileObject(path))
                end

                @testset "dae" begin
                    path = joinpath(base_path, "cube.dae")
                    setobject!(v[:dae], MeshFileObject(path))
                    settransform!(v[:dae], Translation(0, -1.5, 0))
                end
            end
        end

        @testset "textured valkyrie" begin
            geometry = load(joinpath(MeshCat.VIEWER_ROOT, "..", "data", "head_multisense.obj"))
            material = MeshLambertMaterial(
                map=Texture(
                    image=PngImage(joinpath(MeshCat.VIEWER_ROOT, "..", "data", "HeadTextureMultisense.png"))
                )
            )
            setobject!(v[:valkyrie, :head], geometry, material)
            settransform!(v[:valkyrie, :head], Translation(0, 0.5, 0.5))
        end

        @testset "mesh with vertex colors" begin
            # Create a simple mesh with a single triangle
            geometry = GeometryBasics.Mesh(
                [Point(0., 0, 0), Point(1., 0, 0), Point(1., 1, 0)],
                [NgonFace(1, 2, 3)])
            # Wrap that mesh with metadata encoding the vertex colors
            meta_mesh = MetaMesh(geometry, vertexColors=[RGB(1, 0, 0), RGB(0, 1, 0), RGB(0, 0, 1)])
            # Create a Gouraud-shaded material with vertex coloring enabled
            material = MeshLambertMaterial(vertexColors=true)
            # Add it to the scene
            setobject!(v[:vertex_color_mesh], meta_mesh, material)
            settransform!(v[:vertex_color_mesh], Translation(1, -1.5, 0))
        end

    end

    @testset "points" begin
        v = vis[:points]
        settransform!(v, Translation(-1, 0, 0))
        @testset "random points" begin
            verts = rand(Point3f, 100000);
            colors = reinterpret(RGB{Float32}, verts);
            setobject!(v[:random], PointCloud(verts, colors))
            settransform!(v[:random], Translation(-0.5, -0.5, 0))
        end
    end

    @testset "points with material (Issue #58)" begin
        v = vis[:points_with_material]
        settransform!(v, Translation(-1.5, -2.5, 0))
        material = PointsMaterial(color=RGBA(0,0,1,0.5))
        cloud = PointCloud(rand(Point3f, 5000))
        obj = Object(cloud, material)
        @test MeshCat.threejs_type(obj) == "Points"
        setobject!(v, cloud, material)
    end

    @testset "lines" begin
        v = vis[:lines]
        settransform!(v, Translation(-1, -1, 0))
        @testset "LineSegments" begin
            θ = range(0, stop=2π, length=10)
            setobject!(v[:line_segments], LineSegments(Point.(0.5 .* sin.(θ), 0, 0.5 .* cos.(θ))))
        end
        @testset "Line" begin
            θ = range(0, stop=2π, length=10)
            setobject!(v[:line], MeshCat.Line(Point.(0.5 .* sin.(θ), 0, 0.5 .* cos.(θ))))
            settransform!(v[:line], Translation(0, 0.1, 0))
        end
        @testset "LineLoop" begin
            θ = range(0, stop=π, length=10)
            setobject!(v[:line_loop], LineLoop(Point.(0.5 .* sin.(θ), 0, 0.5 .* cos.(θ))))
            settransform!(v[:line_loop], Translation(0, 0.2, 0))
        end
    end

    @testset "Custom geometry primitives" begin
        primitive = CustomGeometry()
        setobject!(vis[:custom], primitive)
        settransform!(vis[:custom],  Translation(-0.5, 1.0, 0) ∘ LinearMap(UniformScaling(0.5)))
    end

    @testset "ArrowVisualizer" begin
        arrow_vis_1 = ArrowVisualizer(vis[:arrow1])
        show(devnull, arrow_vis_1)
        setobject!(arrow_vis_1)
        for l in [range(0, stop=1e-2, length=1000); 1.1 * eps(Float64)]
            settransform!(arrow_vis_1, Point(0, 1, 0), Vec(0, 0, l))
        end
        settransform!(arrow_vis_1, Point(0, 1, 0), Vec(0, 0, 1.1 * eps(Float64)))
        settransform!(arrow_vis_1, Point(0, 1, 0), Vec(1, 1, 1))
        setobject!(vis[:arrow1_base], HyperSphere(Point(0., 1., 0.), 0.015))
        setobject!(vis[:arrow1_tip], HyperSphere(Point(1., 2., 1.), 0.015))

        arrow_vis_2 = ArrowVisualizer(vis[:arrow2])
        setobject!(arrow_vis_2;
            shaft_material=MeshLambertMaterial(color=colorant"lime"),
            head_material=MeshLambertMaterial(color=colorant"indianred"))
        settransform!(arrow_vis_2, Point(0, 1, 0), Point(1, 1, 1))
    end

    @testset "Animation" begin
        anim1 = Animation(vis)
        atframe(anim1, 0) do
            settransform!(vis[:shapes][:box], Translation(0., 0, 0))
        end
        atframe(anim1, 30) do
            settransform!(vis[:shapes][:box], Translation(2., 0, 0) ∘ LinearMap(RotZ(π/2)))
        end
        setanimation!(vis, anim1)
        anim2 = Animation(vis)
        atframe(anim2, 0) do
            setprop!(vis["/Cameras/default/rotated/<object>"], "zoom", 1)
        end
        atframe(anim2, 30) do
            setprop!(vis["/Cameras/default/rotated/<object>"], "zoom", 0.5)
        end
        setanimation!(vis, anim2)
        anim_combined = merge(anim1, anim2)
        @test Set(Iterators.flatten((keys(anim1.clips), keys(anim2.clips)))) == Set(keys(anim_combined.clips))
        setanimation!(vis, anim_combined)
    end
end

@testset "AnimationTrack" begin
    track1 = MeshCat.AnimationTrack{Float64}("foo", "bar")
    @test track1.name == "foo"
    @test track1.jstype == "bar"
    insert!(track1, 0, 32.0)
    @test track1.events == [0 => 32.0]
    insert!(track1, 2, 64.0)
    @test track1.events == [0 => 32.0, 2 => 64.0]
    insert!(track1, 2, 65.0)
    @test track1.events == [0 => 32.0, 2 => 65.0]

    track2 = MeshCat.AnimationTrack{Float64}("foo", "bar")
    insert!(track2, 1, 17.0)
    insert!(track2, 2, 66.0)
    insert!(track2, 5, 1.0)

    merge!(track1, track2)
    @test track1.events == [0 => 32.0, 1 => 17.0, 2 => 66.0, 5 => 1.0]
end

@testset "setvisible!" begin
    v = vis[:box_to_hide]
    setobject!(v, Rect(Vec(0., 0, 0), Vec(0.1, 0.2, 0.3)))
    sleep(1)
    setvisible!(v, false)
    sleep(1)
    setvisible!(v, true)
end

sleep(5)

close(app)
