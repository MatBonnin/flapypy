extends Area3D
## Bonus lâché par un ennemi : flotte en tournant, ramassé au contact.
## L'ordre des types correspond à l'enum Pickup de player.gd.

signal collected(type: int)

const LIFETIME := 12.0

var type := 0
var life := 0.0
var base_y := 0.45

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_build_visual()

func _process(delta: float) -> void:
	life += delta
	rotation.y += 2.5 * delta
	position.y = base_y + sin(life * 3.0) * 0.12
	if life > LIFETIME:
		queue_free()
	elif life > LIFETIME - 2.0:
		# clignote avant de disparaître
		visible = fmod(life, 0.25) > 0.1

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		collected.emit(type)
		queue_free()

func _mesh(mesh: Mesh, pos: Vector3, color: Color, rot := Vector3.ZERO, mesh_scale := Vector3.ONE) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color * 0.3
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = mesh_scale
	add_child(mi)

func _build_visual() -> void:
	match type:
		0:  # coeur
			var lobe := SphereMesh.new()
			lobe.radius = 0.13
			lobe.height = 0.26
			_mesh(lobe, Vector3(-0.08, 0.08, 0), Color(0.9, 0.15, 0.2))
			_mesh(lobe, Vector3(0.08, 0.08, 0), Color(0.9, 0.15, 0.2))
			var point := BoxMesh.new()
			point.size = Vector3(0.2, 0.2, 0.2)
			_mesh(point, Vector3(0, -0.02, 0), Color(0.9, 0.15, 0.2), Vector3(0, 0, 0.785))
		1:  # baguette
			var bread := CapsuleMesh.new()
			bread.radius = 0.08
			bread.height = 0.8
			_mesh(bread, Vector3.ZERO, Color(0.85, 0.65, 0.38), Vector3(0, 0, 1.0))
		2:  # bec d'or
			var cone := CylinderMesh.new()
			cone.top_radius = 0.02
			cone.bottom_radius = 0.14
			cone.height = 0.38
			_mesh(cone, Vector3.ZERO, Color(1.0, 0.82, 0.2), Vector3(1.2, 0, 0))
		3:  # café
			var cup := CylinderMesh.new()
			cup.top_radius = 0.13
			cup.bottom_radius = 0.1
			cup.height = 0.2
			_mesh(cup, Vector3.ZERO, Color(0.95, 0.95, 0.95))
			var coffee := CylinderMesh.new()
			coffee.top_radius = 0.11
			coffee.bottom_radius = 0.11
			coffee.height = 0.03
			_mesh(coffee, Vector3(0, 0.1, 0), Color(0.35, 0.22, 0.1))
		4:  # champignon
			var stem := CylinderMesh.new()
			stem.top_radius = 0.08
			stem.bottom_radius = 0.1
			stem.height = 0.16
			_mesh(stem, Vector3(0, -0.05, 0), Color(0.93, 0.88, 0.78))
			var cap := SphereMesh.new()
			cap.radius = 0.18
			cap.height = 0.36
			_mesh(cap, Vector3(0, 0.08, 0), Color(0.85, 0.2, 0.15), Vector3.ZERO, Vector3(1, 0.65, 1))
			var dot := SphereMesh.new()
			dot.radius = 0.045
			dot.height = 0.09
			_mesh(dot, Vector3(0.1, 0.14, 0.08), Color(1, 1, 1))
			_mesh(dot, Vector3(-0.09, 0.15, -0.05), Color(1, 1, 1))
			_mesh(dot, Vector3(0, 0.12, 0.14), Color(1, 1, 1))
