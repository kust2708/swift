model fire

import "world_cell.gaml"
import "../modelAPIA.gaml"

global
{
	float fire_proba_grow <- 0.4;
	float fire_proba_ungrow <- 0.1;
	float fire_proba_propag <- 0.2;
	int fire_initial_intensity <- 1;
	int fire_max_intensity <- 15;
	int fire_damage_factor <- 2;
	int fire_injury_factor <- 1;
	int fire_init_number <- 10;
	int fire_max_number <- 50;
}

species fire parent: obstacle
{	
	rgb f_color <- #orange;	
	int intensity; // init 1 + rnd growth every turn // <- 5 + rnd(10);
	
	// les feux commencent petits
	init {
		intensity <- fire_initial_intensity;
		shape <- circle(intensity);
	}
	
	// fires grow in intensity randomly over time until a maximum of 15 or 16
	reflex grow  {
		if (flip(fire_proba_grow)) {
			// grow in intensity, up to max (twice?)
			intensity <- min([fire_max_intensity,intensity + rnd(2)]);
		}
		else if (flip(fire_proba_ungrow)) {
			// decrease, down to 0 min
			intensity <- max([0,intensity - rnd(2)]);
		}
		// update shape (radius of circle) with new intensity
		shape <- circle(intensity);		
		cells_should_be_updated <- true;
	}
	
	// propagate always - previously: when intense enough>5
	reflex propagate {
		// propagate to immediate neighbouring cells
		world_cell next;
		using topology(world_cell) {
			next <- shuffle(my_cell neighbors_at 1) first_with (each.my_fire = nil);
		}
		
		// probability of 10 % to propagate to a nearby empty cell (if there is any)
		if (flip(fire_proba_propag) and next != nil) {
			create fire number:1 {
				// select an empty neighbour cell
				location <- next.location;	
				my_cell <- next;
				next.my_fire <- self;
			} 
			world.cells_should_be_updated <- true;
		}
	}
	
	// fires deal damage to all buildings not yet destroyed in their radius
	reflex dealDamage {   
		// list<building> buildingsAround <- building at_distance intensity;
		// question: est-ce que ask prend tous les buildings a la distance ou juste un ?
		
		// buildings avec encore des PV
		list<building> liveBuildings <- (building overlapping self) where (each.resistance>0);
		
		// depends on preparedness of building indirectly (preparedness adds life points)
		// previously "at_distance intensity" mais compte la distance a partir du bord de la shape: trop loin
		ask (liveBuildings) {
			// damage = intensity/(dist+1) - pas de divbyzero
			int decrement <- rnd(myself.intensity*fire_damage_factor); //int(myself.intensity/(distance_to(myself,self.location)+1)) ;
			totalDamage <- totalDamage + decrement;
			resistance <- max([0,resistance - decrement]);
		}
	}
	
	// deal injuries only to not dead and not safe people
	reflex dealInjury {
		// list of pedestrian in intensity radius, alive, not safe (cannot be injured in shelters)
		// overlapping fire shape, and NOT at_distance intensity, because it counts from the border of the shape: too far
		list<pedestrian> livePedestrians <- (pedestrians overlapping self) where (each.health>0 and each.is_safe = false) ;
		
		ask livePedestrians {
			// decrease in health points is function of distance to fire and intensity of fire 
			// injury = intens/(dist+1) pour eviter divbyzero		
			int decrement <- rnd(myself.intensity*fire_injury_factor); //int(myself.intensity/(distance_to(myself,self.location)+1));
			// injury should be weighted by the protection offered by the building
			building maMaison <- myBuilding;
			bool atHome <- location = myBuilding.location;
			// injury divided by 1,2,3,4 depending on resistance of building
			if (atHome and myBuilding.resistance > 0) {
				decrement <- int(decrement / (int(myBuilding.resistance*building_protection_factor)+building_min_protection));
			}
			//write("pedestrian in state "+state+" receives injury while at home is "+atHome);
			totalInjury <- totalInjury+decrement;
			injuries <- injuries+decrement;
			// random decrease in that range, but stay positive or null
			decrement <- abs(decrement);
			health <- max([0,health - decrement]);
		}
	}
	
	action die_properly {
		world.cells_should_be_updated <- true;
		my_cell.my_fire <- nil;
		intensity <- 0;
		do die;
	}
	
	// fire dies if intensity<0 (from firefighters), or randomly, or at end of 500 cycles of simulation
	reflex disappear {
		// proba of 0.01% to die
		if flip(0.001) {
			do die_properly;
		} 
		// die from firefighters if intensity gets negative
		// die after 500 cycles of simulation
		// limit the max number of fires
		if (intensity<=0 or cycle>500 or length(fire)>fire_max_number) {
			do die_properly;
		}
		
		if length(shelter overlapping self) > 0 {
			//write "no fire in shelter";
			do die_properly;
		}
	}
		
	aspect basic {
		draw triangle(1) color: f_color;
	}	
}

