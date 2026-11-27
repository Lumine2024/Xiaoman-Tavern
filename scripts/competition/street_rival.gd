extends RefCounted
## v0.4 pilot. All authored content and tunable values live in street_rival.json.
var data: Dictionary = preload("res://scripts/game/resource_data.gd").read("res://data/street_rival.json")
var challenge_mode = false

func _init() -> void:
	var prose: Dictionary = preload("res://scripts/game/resource_data.gd").read("res://data/story.json").street
	data.text = prose.text
	data.habits = prose.habits
	data.captain.beats = prose.captain_beats
	for id in data.cards: data.cards[id].merge(prose.cards[id])
	for id in data.responses: data.responses[id].label = prose.responses[id]

func fresh() -> Dictionary:
	return {"enabled": false, "upper_hand": false, "escalated": false, "card": "", "changed": false, "changed_day": 0, "respect": 0, "favorable": 0, "card_streak": 0, "last_card": "", "copies": [], "disabled_day": 0, "hit_loss": 0, "hold_streak": 0, "visit_answer": "", "notices": [], "ending": "", "captain": {"visits": 0, "last_day": 0, "last_line": "", "answer": -1, "left": false}}

func choose(s: Dictionary, card: String, day: int) -> bool:
	if not data.cards.has(card) or not data.cards[card].enabled: return false
	if not s.card.is_empty() and (day != int(data.numbers.change_day) or s.changed): return false
	if s.card == card: return false
	if not s.card.is_empty():
		s.changed = true
		s.changed_day = day
	s.card = card
	return true

func effective(s: Dictionary, day: int) -> String:
	return "" if int(s.disabled_day) == day or not s.ending.is_empty() else str(s.card)

func begin(s: Dictionary, state: Dictionary, recipe: Dictionary, day: int, premium = false) -> void:
	if not s.ending.is_empty(): return
	s.notices = []
	s.hit_loss = 0
	var n: Dictionary = data.numbers
	s.card_streak = int(s.card_streak) + 1 if s.last_card == s.card else 1
	s.last_card = s.card
	for copy in s.copies:
		if int(copy.day) != day: continue
		if copy.kind == "card" and copy.target == s.card:
			if not copy.half: s.disabled_day = day
			else: s.hit_loss = int(n.copy_hit_loss)
			s.notices.append(data.text.copied_half if copy.half else data.text.copied_card)
		elif copy.kind == "recipe" and copy.target == recipe.id and recipe.method != data.immune_method and not premium:
			s.hit_loss = int(n.copy_hit_loss)
			s.notices.append(data.text.copied_recipe)
	if state.rival == "karn":
		if day == int(n.rumor_day): s.notices.append(data.text.rumor)
		if day >= int(n.pressure_day): s.notices.append(data.text.pressure)
		if day == int(n.visit_day) and s.upper_hand:
			var yesterday = str(state.history[-2].recipe_id) if state.history.size() > 1 else ""
			s.notices.append(data.text.visit.format({"yesterday": yesterday}))
		if day == int(n.escalation_day) - (int(n.irony_advance) if s.visit_answer == "irony" else 0) and s.upper_hand:
			s.escalated = true
			s.notices.append(data.text.escalation_tones["polite" if int(s.respect) > 0 else ("harsh" if int(s.respect) < 0 or s.visit_answer == "silent" else "cold")])
		if day == int(n.ending_day) and not challenge_mode:
			s.ending = "alliance" if int(s.favorable) >= int(n.alliance_choices) and int(s.respect) >= int(n.alliance_respect) else ("counterplay" if int(s.hold_streak) >= int(n.hold_days) else "coexist")
			s.notices.append(data.text.endings[s.ending])
	if s.copies.size() < int(n.max_copies) and state.rival == "karn" and day < int(n.ending_day):
		var kind = "card" if int(s.card_streak) == int(n.observe_days) else ("recipe" if int(state.promotion_streak) == int(n.observe_days) else "")
		if not kind.is_empty():
			s.copies.append({"kind": kind, "target": s.card if kind == "card" else recipe.id, "day": day + int(n.copy_delay), "half": not s.copies.is_empty()})
			s.notices.append(data.text.learning)
	if s.notices.is_empty(): s.notices.append(data.habits[state.rival][(day - 1) % data.habits[state.rival].size()])

func traffic(s: Dictionary, state: Dictionary, recipe: Dictionary, day: int) -> int:
	if not s.ending.is_empty(): return 0
	var n: Dictionary = data.numbers
	var card = effective(s, day)
	var delta = int(data.cards.get(card, {}).get("traffic", 0))
	for copy in s.copies:
		if int(copy.day) == day and copy.half and copy.kind == "card" and copy.target == s.card: delta = 0
	if state.rival == "karn" and day >= int(n.pressure_day) and recipe.id in data.price_recipe_ids and card not in ["follow", "offset"]: delta += int(n.price_traffic)
	if int(s.changed_day) == day: delta += int(n.change_traffic)
	if s.escalated and day >= int(n.escalation_day) - (int(n.irony_advance) if s.visit_answer == "irony" else 0) + 1 and state.rival == "karn": delta += int(n.escalation_traffic)
	if day == int(n.visit_day) and state.rival == "karn" and not s.visit_answer.is_empty(): delta += int(n.visit_traffic)
	if day == int(n.visit_day) and state.rival == "karn" and s.visit_answer == "reply": delta += int(n.reply_traffic)
	return clampi(delta, -int(n.traffic_cap), int(n.traffic_cap))

func respond(s: Dictionary, answer: String, day: int) -> bool:
	if not s.upper_hand or day != int(data.numbers.visit_day) or not s.visit_answer.is_empty() or not data.responses.has(answer): return false
	s.visit_answer = answer
	var response: Dictionary = data.responses[answer]
	s.respect = clampi(int(s.respect) + int(response.respect), -int(data.numbers.respect_cap), int(data.numbers.respect_cap))
	if int(response.respect) > 0: s.favorable += 1
	return true

func close(s: Dictionary, state: Dictionary, recipe: Dictionary, day: int) -> void:
	s.upper_hand = traffic(s, state, recipe, day) < 0 or int(s.disabled_day) == day
	if state.rival == "karn" and day >= int(data.numbers.pressure_day):
		s.hold_streak = int(s.hold_streak) + 1 if effective(s, day) != "follow" else 0

func captain_guest(s: Dictionary, guest: Dictionary, day: int, interrupted: bool) -> void:
	var c: Dictionary = s.captain
	if guest.get("story_id", "") != data.captain.id or c.left or int(c.visits) >= data.captain.beats.size() or interrupted: return
	guest.erase("choices")
	var beat: Dictionary = data.captain.beats[int(c.visits)]
	guest.topic = beat.get("alternate_line", beat.line) if int(c.answer) == 1 else beat.line
	guest.answers = beat.answers.duplicate()
	guest.good_answer = 0
	guest.reply = beat.reply
	guest.longline_beat = beat
	guest.longline = true
	guest.longline_answer = -1

func captain_served(s: Dictionary, guest: Dictionary, day: int) -> void:
	if not guest.get("longline", false) or int(guest.longline_answer) < 0: return
	var c: Dictionary = s.captain
	c.last_day = day
	c.last_line = guest.topic
	c.answer = int(guest.longline_answer)
	c.visits += 1
	if int(c.visits) == data.captain.beats.size() and c.answer == 1: c.left = true
