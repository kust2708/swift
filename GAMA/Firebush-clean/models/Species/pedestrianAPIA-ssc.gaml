model pedestrianAPIA

import "../modelAPIA.gaml"

species pedestrianSSC parent: pedestrian control: fsm schedules: (pedestrianSSC where not (each.is_dead or each.is_safe)){ 
	
	reflex perceive_fires {
		ask ((fire at_distance perception_radius)-known_fires) {
 			add self to: myself.known_fires;
 		} 		
 	}
 	
 	reflex perceive_shelters {
 		ask (list(shelter) - known_shelters) {
 			add self to: myself.known_shelters;
 		} 
 	}

	state unaware initial: true{
		enter {
			color <- #darkblue;
		}
		transition to: active_indecisive when: flip(awarness_probability) and not empty(known_fires) ;	
	}
	
	state active_indecisive {
		enter {
			color <- #pink;
		}
		transition to: prepare_to_defend when: flip(defend_motivation);
 		transition to: prepare_to_escape when: flip(escape_motivation) ;
	}

	state prepare_to_defend {
		enter {
			color <- #orange;
		}
		do prepare_for_fire;
		transition to: defend when:  distance_closest_hot <= people_defense_radius;
	} 
	 
	state defend {
		enter {
			color <- #red; 	
 		}
		do fight_fire;
		transition to: prepare_to_defend when:  distance_closest_hot > people_defense_radius; 
		transition to: escape when: escape_motivation>defend_motivation {
			color <- #purple;
		} 	
	}


	state prepare_to_escape {
		enter {
			color <- #yellow;	
 		}
		do prepare_for_fire;
		transition to: escape when: myBuilding.resistance>building_fire_ready and escape_motivation>0.5;
		transition to: escape when: (distance_closest_hot <= people_defense_radius) ;
		transition to: prepare_to_defend when: empty(my_cell.neigh where (each.distance!=-1 or each.emergency_distance!=-1)) ;
	}
	
	state escape {
		enter {
			color <- #aqua; 
 		}
 		do moving;
 		transition to: safe when: (my_cell.cover = SHELTER_CELL) {
			color <- #green;
		}	
	}
	
	state safe  {
		enter {
			is_safe <- true;
			color <- #green;
		}
	}
}


