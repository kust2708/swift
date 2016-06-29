model pedestrian

import "../modelAPIA.gaml"

species pedestrian skills: [moving]{
	
	bool did_preparation <- false;
	bool did_preparation_stay <- false;
	bool took_by_surprise_D <- false;
	bool unaware <- true;
	bool escaping_D <- false;
	bool defending_D <- false;
	bool in_the_house_D <- false;
	bool escaping <- false;
	bool fighting_fire <- false;
	
	/***********************
	 * PHYSICAL ATTRIBUTES *
	 ***********************/
	// health, initially random value, then updated by fire dealing injuries
	int health <- 50+rnd(100) min:0;
	int initial_health <- health;
	// total received injury because no memory of initial health
	int injuries <- 0;

	// standard attributes
	rgb color <- #blue;
	rgb border <- #black;
	float size <- 0.5; // circle size
	world_cell my_cell; //cell used by the agent
	building myBuilding; // the agent's house


	/*****************************
	 * PSYCHOLOGICAL  ATTRIBUTES *
	 *****************************/

	bool is_safe <- false; // define if the agent is in a safe place like a shelter
	bool is_dead <- false; // define if  the agent is dead or still alive
	bool in_smoke <- false; // define if the agent is in the in_smoke

	float defend_motivation min:0.0 max:1.0 <- 0.5 + rnd(0.5);
	float escape_motivation min:0.0 max:1.0  <- 0.2 + rnd(0.8);
	float objective_ability min:0.0 max:1.0  <- rnd(1.0);
	float fighting_actions;
	float awarness_probability <- rnd(0.5);	
	
	float perception_radius min: 0.0 max: 20.0 <- rnd(20.0); // determine the perception radius
	float defense_radius min: 0.0 <- rnd(2.0); // determine the area of defense, if a fire enter in this area the agent begin to fight agains.
	float danger_radius min: 0.0 max: 10.0 <- rnd(10.0); // determine the danger radius
	float velocity min:0.2 max:8.0 <- rnd(0.8)+0.2; // get an equiprobable value in the interval [0.2; 1.0]

	list<fire> known_fires update:known_fires where (not dead(each) and (each.intensity >0));
		
	list<shelter> known_shelters; // list of known shelters 
	int cyclesInDefense;
	
	list<world_cell> cells_hot update: (world_cell(location) neighbors_at people_defense_radius)where (each.cover=HOTSPOT_CELL);
	world_cell closest_hot_cell <- nil update: empty(cells_hot) ? nil: cells_hot with_min_of (each.location distance_to location);
	int distance_closest_hot update: (closest_hot_cell=nil)?1000:int(self distance_to closest_hot_cell);
	
	shelter closest_shelter; // closest shelter from the agent position
	
	init
	{
		self.speed <- velocity;
		ask shelter
		{
			if(flip(0.8))
			{
				add self to: myself.known_shelters;
			}
		}
	}
	
	action prepare_for_fire {
		did_preparation <- true;
		did_preparation_stay <- true;
		fighting_fire <- true;	
		unaware <- false;
		int preparationEffect <- int(rnd(people_preparation_factor*objective_ability));
 		ask myBuilding {
			resistance <- min([building_max_resistance,resistance+preparationEffect]);
		}
		health <- min([health+preparationEffect,max_health]);
 	}
 	
 	action fight_fire {
 		fighting_fire <- true;
 		did_preparation <- true;
		did_preparation_stay <- true;	
		unaware <- false;
 		int fightingEffect <- int(rnd(people_fighting_factor*objective_ability));
		ask fire at_distance (people_defense_radius) {
			intensity <- intensity - fightingEffect;
			shape <- circle(intensity);
			myself.fighting_actions <- myself.fighting_actions + fightingEffect;
			
		}
		cyclesInDefense <- cyclesInDefense +1;
	}
	
	action moving {
		unaware <- false;
		did_preparation <- true;	
		escaping <- true;
		fighting_fire <- false;
		in_smoke <-(self.my_cell.cover in [HOTSPOT_CELL,FIRE_CELL]);
		point prev_loc <- copy(location);
		bool try_heuristic_move <- empty(known_shelters);
		bool stuck <- not ((world_cell(location).neighbors) first_with (each.cover in [EMPTY_CELL]) != nil);
		if(not try_heuristic_move)
		{
			bool need_to_recompute <- ((world_cell(location).neighbors) first_with (each.cover in [HOTSPOT_CELL,FIRE_CELL]) != nil) ;
			if (closest_shelter = nil)
			{
				closest_shelter <- known_shelters closest_to self;
			}
			do goto
				target: closest_shelter
				on: world_cell where (each.cover = EMPTY_CELL or each.cover = SHELTER_CELL)
				recompute_path: need_to_recompute;
			try_heuristic_move <- prev_loc = location;
		}
		else if(try_heuristic_move)
		{
			list<fire> close_fires <- fire at_distance(perception_radius);
			if not empty(close_fires)
			{
				float direction <-  mean (close_fires collect float(self towards each)) - 180;
				do move heading:direction;
			}
			if (location = prev_loc) 
			{
				do wander amplitude: 45;
			}
		}

		self.color <- (stuck and not self.myBuilding.destroyed and location = myBuilding.location) ? #silver : #aqua;
	}
	
	reflex update_speed 
	{
		// the agent's speed is proportional to his health
		self.speed <- ((health*velocity)/initial_health);
		// reduce the speed when the agent is in smokes (20%)
		self.speed <- ((in_smoke) ? self.speed-0.2*self.speed : self.speed);
	}
	
	reflex update_motiv_fight {
 		if (myBuilding.resistance = 0) {
 			defend_motivation <- 0.0;
 		}
 		else if ((my_cell.neigh count (each.distance!=-1 or each.emergency_distance!=-1))=0) {
 			defend_motivation <- 1.0;
 		}
 		else {
 			float injury_per_cycle <- injuries/cyclesInDefense;
 			float cycles_before_death <- (injury_per_cycle>0)?health/injury_per_cycle:1000000;
 			
 			float damage_per_cycle <- myBuilding.damage / cyclesInDefense;
 			float cycles_before_destroyed <- (damage_per_cycle>0)?myBuilding.resistance/damage_per_cycle:1000000;
 			
 			float water_per_cycle <- fighting_actions/cyclesInDefense;
 			float cycles_before_extinction <- (water_per_cycle>0)?sum((known_fires where !dead(each)) collect each.intensity)/water_per_cycle:1000000;
 			
 			if (min([cycles_before_death,cycles_before_destroyed]) < cycles_before_extinction) {
 				defend_motivation <- defend_motivation * (1-motivation_update_rate);
 			}
 			else {
 				defend_motivation <- defend_motivation+(1-defend_motivation)*motivation_update_rate ;
 			}
		}
 	}
 	

	reflex death when: health<= 0 {
		rgb mem <- self.color;
 		self.color <- #black;
 		self.border <- mem;
		self.is_dead <- true;
		numberDead <- numberDead+1;
		escaping_D <- escaping;
		
		in_the_house_D <- self.location = myBuilding.location and not fighting_fire and not escaping;
		took_by_surprise_D <- unaware;
	}
	
	aspect basic
	{
		draw circle(size) color: color border: border;
	}
	
	
}