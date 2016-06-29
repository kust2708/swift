model pedestrianAPIA

import "../modelAPIA.gaml"

species pedestrianBDI parent: pedestrian control: simple_bdi schedules: (pedestrianBDI where not (each.is_dead or each.is_safe)){
	
	predicate stay_alive <- new_predicate("Stay alive") with_priority escape_motivation ;
	predicate protect_property <- new_predicate("Protect their property") with_priority defend_motivation update: protect_property with_priority defend_motivation;
	bool aware update: flip(awarness_probability/2);
	
	perceive target:(list(fire) - known_fires) in: perception_radius 
	{
		add self to: myself.known_fires;
	}
	
	perceive target:(list(shelter) - known_shelters) in: perception_radius
	{
		add self to: myself.known_shelters;
	}
	
	rule when: not empty(known_fires) and aware new_desire: stay_alive;
	rule when: not empty(known_fires) and aware new_desire: protect_property;
	
	plan prepare_property intention: protect_property when:  distance_closest_hot > people_defense_radius {
		self.color <- #orange;
		do prepare_for_fire;
	}
 
	plan fight_fire intention: protect_property when:  distance_closest_hot <= people_defense_radius 
	{
		self.color <- #red;
		do fight_fire;
		if escape_motivation>defend_motivation {do remove_intention(protect_property,true);}
	}
	
	plan go_to_shelter intention: stay_alive
	{
		do moving;
		if (my_cell.cover = SHELTER_CELL)
	    {
	    	self.is_safe <- true;
			self.color <- #lime;
		}
	}
}
