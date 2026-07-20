class_name Brain
extends Node
## Базовый компонент-«мозг» игрока (Фаза 2). Живёт дочерним узлом тела (player.tscn);
## тело своё берёт как _body := get_parent(). Ничего не двигает в _ready — поля (ball и т.п.)
## инъектит фабрика ПОСЛЕ add_child, поэтому _ready кэширует только _body.
## Полевые мозги пушат намерение в мотор через _drive()/_stop(); movement_intent()/speed_scale()
## — читаемый seam для Фазы 3 (человек-мозг), в Фазе 2 их драйв остаётся внутри каждого мозга.

var _body: CharacterBody3D
var _intent: Vector3 = Vector3.ZERO
var _intent_scale: float = 0.0

func _ready() -> void:
	_body = get_parent() as CharacterBody3D

## Тело, к которому прикреплён этот мозг (то, чем скрипт «был» до компонентизации).
func body() -> CharacterBody3D:
	return _body

## Непрерывное состояние движения (seam Фазы 3). В Фазе 2 — последнее, что мозг задал мотору.
func movement_intent() -> Vector3:
	return _intent

func speed_scale() -> float:
	return _intent_scale

## Вкл/выкл мозга — глушим/возвращаем его физпроцесс (заморозка на голе/сет-писе).
func set_active(on: bool) -> void:
	set_physics_process(on)

## Полевой драйв: запомнить намерение (для геттеров) И толкнуть его в PlayerMotor тела.
func _drive(dir: Vector3, scale: float = 1.0) -> void:
	_intent = dir
	_intent_scale = scale if dir.length() > 0.001 else 0.0
	var m := PlayerMotor.find_on(_body)
	if m != null:
		m.set_move_intent(dir, scale)

func _stop() -> void:
	_drive(Vector3.ZERO, 0.0)
