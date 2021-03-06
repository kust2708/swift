/**
 *  modelAPIA
 *  Author: bgaudou and cadam
 *  Description: 
 */

model modelAPIA

import "pedestrianAPIA.gaml"

/**
 * TODO NEXT 
 *   - monitoring functions so that agents update their subjective view of danger as fires get bigger and closer
 *   - monitoring of success/failure of actions so that agents update their view of their fighting abilities
 *   - transitions from defender to escaper when balance is broken between capabilities and perceived danger (SD>SC)
 *   - graphs and stats about the outcome of the simulation
 *   - button to trigger rain to clear the fire in the middle of the simulation
 *   - plus de graphiques
 *   - chercher source du ralentissement final
 *   - definir des parametres globaux pour toutes les valeurs empiriques: duree (50 cycles), 
 *             nombre d'agents (100), rayon de danger/degat/blessure, etc
 */


global {

	bool cells_should_be_updated <- false;

	// compteurs du nombre d'agents dans les differents etats
	int numberDead <- 0;
	int numberSheltered <- 0;
	int numberDefended <- 0;
	
	int numberDefenders <- 0;
	int numberEscapers <- 0;
	int numberIndecisive <- 0;
	int numberDestroyed <- 0;
	
	// stats
	int totalDamage <- 0;
	int totalInjury <- 0;
	//int fightingActions <- 0;
	
	
	/**********************
	 * *** PARAMETERS *** * 
	 **********************/
	
	// Parameters
	int nb_people <- 200;
	int max_health <- 300;
	
	// fire related 
	float fire_proba_grow <- 0.4;
	float fire_proba_ungrow <- 0.1;
	float fire_proba_propag <- 0.1;
	//float fire_distance_injury <- 10.0;
	int fire_initial_intensity <- 1;
	int fire_max_intensity <- 15;
	int fire_damage_factor <- 3;
	int fire_injury_factor <- 1;
	int fire_init_number <- 10;
	int fire_max_number <- 50;
	
	// building related
	int building_max_resistance <- 300;
	float building_protection_factor <- 0.01;
	int building_min_protection <- 2;
	// building resistance that is enough to be left alone in the fire (end of preparation)
	int building_fire_ready <- 200;
	float shelter_size <- 3.0; // Shelters size
	
	// people related		
	// radius where peple with max objective ability of 1 will detect the fire
	int people_further_awareness <- 15;
	// some probability so that agents have a chance to be surprised
	float proba_detection <- 1.0;
	// max radius for counting fires when evaluating danger, for people with max risk_aversion of 1
	int people_further_aversion <- 10;
	// radius to impact fire
	int people_defense_radius <- 4;
	// multiplying factor for preparation actions and defense actions (based on objective ability)
	int people_preparation_factor <- 10;
	int people_fighting_factor <- 15;
	// motivation update rate : how fast the motivation decays in adverse condition, and increases in positive conditions
	// 0 = min speed (no change), 1= max speed (drops to 0 or increases to 1 directly) 
	float motivation_update_rate <- 0.2;
	// ability update rate : how fast the subjective ability is updated based on observations
	float ability_update_rate <- 0.3;
	
	int hotspot_path_malus <- 10;
	
	// world variables
	// distance for fires to deal damage / injury
	// int damage_threshold <- 3;
	
	// Constants 
	string EMPTY_CELL <- "";
	string BUILDING_CELL <- "building";
	string FIRE_CELL <- "on_fire";
	string HOTSPOT_CELL <- "hot";
	string SHELTER_CELL <- "shelter";
	
	list<world_cell> forbiden_zones <- [];

	// 
	string save_trajectory_file_path <- "../results/pedestrians"+machine_time+".txt";
	string save_traj_for_analysis <- "../results/p200.txt";
	string save_csv_for_analysis <- "../results/p200.csv";

	init {
		create shelter number:1 {
			location <- world_cell({95,5}).location;
			world_cell({95,5}).cover <- SHELTER_CELL;
		}
		create shelter number:1 {
			location <- world_cell({5,95}).location;
			world_cell({5,95}).cover <- SHELTER_CELL;
		}	
		
 		ask world_cell
 		{
 			if(self.cover = SHELTER_CELL)
 			{
 				forbiden_zones <- forbiden_zones + (self neighbors_at shelter_size);
			}
 		}
		
		create pedestrian number:nb_people {
			// TODO: no fires should be created too close to shelters
			my_cell <- one_of(world_cell 
				where (
					each.cover != FIRE_CELL 
					and each.cover != BUILDING_CELL 
					and each.cover != SHELTER_CELL 
					and not (each in forbiden_zones)
				)
			);
			location <- my_cell.location;		
			
			create building returns: createdBuildings {
				my_cell <- myself.my_cell;
				location <- my_cell.location;
				owner <- myself;
			}
			
			myBuilding <- first(createdBuildings);
			
			ask my_cell {
				cover <- BUILDING_CELL;			
			}
		}				
		
		write ("*** START OF FIRE ***");
		write ("people: "+length(pedestrian)+" in buildings: "+length(building));
		
		do start_fire with: [how_many::fire_init_number]; //ici
	
	}//end init global
	
	// user commands to start and stop fire
	user_command "Start some fires !!!" { //action: start_fire with: [how_many::user_input(["How many?"::10])];
		write ("starting fires !!!");
		int n<- 10;
        map input_values <- user_input(["How many?" :: n]);
        //do start_fire how_many: n; // with: [how_many::n];
        do start_fire how_many: int(input_values["How many?"]);
      }
	
	
	action start_fire (int how_many) {
		// FIXME: how to get the number of fires to create as a user input?
		//user_input(["Number" :: 100]);
      	//create fire number : int(values at "Number");
		
		create fire number:how_many {
			my_cell <- one_of(world_cell 
				where (
					each.cover != FIRE_CELL
					and each.cover != BUILDING_CELL
					and each.cover != SHELTER_CELL 
					and not (each in forbiden_zones)
				)
			);
			location <- my_cell.location;
			ask my_cell {
				my_fire <- myself;
				cover <- FIRE_CELL;
			}
		}
		// update covers and path : this boolean will trigger the reflex update_cells
		cells_should_be_updated <- true; 		
		
	}
	
	user_command stop_fire action: stop_fire;
	action stop_fire {
		ask fire {
			do die_properly;
			// sets the cells_should_be_updated boolean that will trigger the reflex update_cells
		}
	}
	
	// simulation ends automatically once all people agents are dead (safe in shelter or dead in fire)
	// do not do at the start...
	reflex thatsallfolks when: cycle>2 and (empty(pedestrian where (each.health>0)) or empty(fire))
	{
		numberDefended <- 0;
		ask pedestrian
		{
			if (!myBuilding.destroyed and (color = #red or color = #orange))
			{
				numberDefended <- numberDefended+1;
			}
		}
		
		numberEscapers <- length(pedestrian where (color = #aqua));
		
		write ("entering reflex at cycle "+cycle);
		// if do die, closes the graph as well
		write("*** END OF FIRE ***");
		write ('survivors = '+numberSheltered+' in shelters, '+numberDefended+' successful defenders');
		write ('dead = '+numberDead);
		write ('others = '+(nb_people-numberDead-numberSheltered-numberDefended));
		
		write("defenders: "+numberDefenders);
		write("escapers: "+numberEscapers);
		write("still indecisive: "+numberIndecisive);
		
		write("buildings destroyed: "+length(building where (each.destroyed)));
		

		
		/*ask pedestrian {
			// save the values of the variables name, speed and size to the csv file
			save [name,initial_health,knows_how_to_fight_fire,is_safe,is_leaving,is_dead,determination,persuadabillity,danger_aversion,perception_radius,defense_radius,velocity] 
				to: "../results/pedestrians.csv" type:"csv";
		}*/

		// TODO faire les stats ! cf TrajectoryStats.gaml 

		do pause;
	}
	
	reflex update_cells when: cells_should_be_updated {
		ask world_cell {
			do update_cell_cover;
		}				
		cells_should_be_updated <- false;
				
	}
	
	action updatePath {
		ask world_cell {
			neigh_with_hotspots <- (self neighbors_at 1) 
				where ((each.cover != FIRE_CELL) and (each.cover != BUILDING_CELL));
			
			neigh <- neigh_with_hotspots where (each.cover != "hot");
			distance <- -1;	
			emergency_distance <- -1;
			nb_hot_spots <- 0;
		}
		
		list<world_cell> nextPlots <- world_cell where (each.cover = SHELTER_CELL);
		ask nextPlots {
			distance <- 0;
			emergency_distance <- 0;
		}
		list<world_cell> neighs <- remove_duplicates(nextPlots accumulate (each.neigh_with_hotspots));
		nextPlots <- neighs where (each.distance = -1);
		
		int dist <- 0;
		
		loop while: !empty(nextPlots) {
			neighs <- [];
			rgb r_color <- rnd_color(255);
			ask nextPlots {
				if(self.cover != HOTSPOT_CELL) {
					list<world_cell> neigh_with_positive_distance <- neigh_with_hotspots where(each.distance != -1);
					
					distance <- empty(neigh_with_positive_distance) ? -1 : (neigh_with_positive_distance min_of(each.distance)) + 1;
				} // else it keeps its -1 value
				
				world_cell c <- (neigh_with_hotspots where (each.emergency_distance !=-1)) with_min_of(each.emergency_distance);
				emergency_distance <- c.emergency_distance + 1 + ((self.cover = HOTSPOT_CELL)?hotspot_path_malus:0);
				nb_hot_spots <- c.nb_hot_spots + ((self.cover = HOTSPOT_CELL)?1:0);

				neighs <- neighs + self.neigh_with_hotspots where ((each.emergency_distance = -1) or (each.emergency_distance > self.emergency_distance));
			}
				
			nextPlots <- remove_duplicates(neighs);
		}
	}

}


grid world_cell width: 50 height: 50 neighbors: 8 use_individual_shapes: false use_regular_agents: false frequency: 0{
	list<world_cell> neigh;
	list<world_cell> neigh_with_hotspots;
	rgb color <- #greenyellow ;
	string cover <- EMPTY_CELL among: [EMPTY_CELL,BUILDING_CELL,FIRE_CELL,HOTSPOT_CELL,SHELTER_CELL];
	fire my_fire <- nil;
	building my_building <- nil;
	bool is_empty <- true;
	
	// Shortest Paths to shelter
	int distance <- -1;				// for safe path
	int emergency_distance <- -1;			// path that can be through hot spots (with a weight)
	int nb_hot_spots <- 0;					// nb of hot spot on path from shelter
	
	// update cover and color
	// only called in the update_cells reflex, triggered when the cells_should_be_updated boolean is true
	action update_cell_cover {
		if(cover != SHELTER_CELL) and (cover != BUILDING_CELL){
			if(my_fire != nil) {
				cover <- FIRE_CELL;
			} else if (!empty(fire overlapping(self))) {
				cover <- HOTSPOT_CELL;
			}	
			else {
				// cover reset if fire disappears 
				cover <- EMPTY_CELL;
			}	
		}
		color <- self getColor();
	}
	
	rgb getColor {
		switch cover {
			match FIRE_CELL {
				return #red;
			}
			match HOTSPOT_CELL {
				return #yellow;
			}
			// building not on fire
			match BUILDING_CELL {
				return #grey;
			}
			// shelter and open area
			default {
				return #greenyellow;
			}
		}
	}
	
	aspect path {
		draw square(2) color: rgb(distance*10,distance*10,distance*10);
	}
	
	aspect emergency_path {
		draw square(2) color: rgb(emergency_distance*10,emergency_distance*10,emergency_distance*10);
	}
}

species shelter {
	aspect basic {
		draw circle(shelter_size) border: #black color:#magenta;
	}	
}

species obstacle {
	world_cell my_cell;
}

species fire parent: obstacle {	
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
		list<pedestrian> livePedestrians <- (pedestrian overlapping self) where (each.health>0 and each.is_safe = false) ;
		
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

species building parent: obstacle {
	pedestrian owner;
	//float destructionRate <- 0.0;
	bool destroyed <- false;
	rgb b_color <- #grey;
	
	// preparedness, vulnerability, lifepoints, altogether in one resistance attribute	
	int resistance <- 100+rnd(100);
	int initial_resistance <- resistance;
	// remember how much damage was taken
	int damage <- 0;
	
	// when all life points are lost, building turns into a ruin but stays there
	reflex getDestroyed when: !destroyed and (resistance <= 0) {
		// leave a ruin in the simulation
		b_color <- #black;
		destroyed <- true;
		resistance <- 0;
		// do die;
		numberDestroyed <- numberDestroyed+1;
	}
	
	aspect basic {
		draw square(1.5) color: b_color border: #black;
	}
}


experiment fire_batch type:batch repeat: 10 until:(time > 500) {
	parameter "Initial number of people" var: nb_people min: 0 category:"Initial values";
	
	// Fire
	parameter "Fire probability to grow" var: fire_proba_grow min:0.0 max:1.0 category: "Fire";
	parameter "Fire probability to de-grow" var: fire_proba_ungrow min:0.0 max:1.0 category: "Fire";
	parameter "Fire probability to propagate" var: fire_proba_grow min:0.0 max:1.0 category: "Fire";
	parameter "Fire initial intensity" var: fire_initial_intensity min:0 max:20 category: "Fire";
	parameter "Fire maximum intensity" var: fire_max_intensity min:0 max:20 category: "Fire";
	parameter "Fire damage factor (to buildings)" var: fire_damage_factor init:3 min: 1 max: 10 category: "Fire";	
	parameter "Fire injury factor (to people)" var: fire_injury_factor init:1 min: 1 max: 10 category: "Fire";	
	parameter "Initial number of fires" var:fire_init_number init:10 min:0 max:100 category: "Fire";
	parameter "Max number of fires" var:fire_max_number init:50 min:10 max:100 category: "Fire";
	
	// People
	parameter "People furthest radius of awareness" var:people_further_awareness min: 1 init: 15 category: "People";
	parameter "Probability to detect fire in radius of awareness" var:proba_detection init:1.0 category: "People";
	parameter "People furthest radius to get aware of fire" var:people_further_aversion min:1 init: 10 category: "People";
	parameter "People max radius to impact fire" var:people_defense_radius min:1 init: 4 category: "People";
	parameter "People preparation factor (max preparation action)" var:people_preparation_factor min:1 init: 10 category:"People";
	parameter  "People fighting factor (max defense action)" var:people_fighting_factor min:1 init: 15 category:"People";
	parameter "People motivation update rate" var: motivation_update_rate min:0.0 max:1.0 init:0.2 category: "People";
	parameter "People confidence update rate" var: ability_update_rate min:0.0 max:1.0 init:0.2 category: "People";
	
	// Buildings
	parameter "Building maximum resistance level" var: building_max_resistance init: 300 min:0 max:300 category: "Building";
	parameter "Building resistance to be fire ready" var:building_fire_ready min:0 max:300 init:200 category: "Building";
	parameter "Building protection factor (against fire injuries)" var:building_protection_factor init:0.01 min: 0.0 max: 0.5 category: "Building";
	parameter "Building minimum protection" var:building_min_protection init:2 min:1 max:5;
	
	
	output {
		display LastPlan {
			chart "Last plan used before dying" type:pie {
				datalist ["Unaware","Does nothing","Covered at home","Goes to shelter","Seeks information","Prepare property","Fights fire"]
				value:[
					length(pedestrian where (each.is_dead and each.last_plan=0 and !each.aware)),
					length(pedestrian where (each.is_dead and each.last_plan=0 and each.aware)),
					length(pedestrian where (each.is_dead and each.last_plan=1)),
					length(pedestrian where (each.is_dead and each.last_plan=2)),
					length(pedestrian where (each.is_dead and each.last_plan=3)),
					length(pedestrian where (each.is_dead and each.last_plan=4)),
					length(pedestrian where (each.is_dead and each.last_plan=5))
				]
				color:[#blue,#steelblue,#silver,#aqua,#green,#orange,#red] line_visible:true;				
			}
		}
		
		display Profils {
			chart "Pedestrian profils" type:pie {
				datalist ["Unaware reactors","Threat avoiders","Threat monitors","Can-do defenders","Considered defenders"]
				value:[
					length(pedestrian where (each.does_nothing and !each.goes_to_shelter and !each.takes_cover_at_home and !each.seeks_information and !each.prepares_property and !each.fights_fire and each.has_belief(each.belief_danger))),
					length(pedestrian where (each.goes_to_shelter and !each.takes_cover_at_home and !each.seeks_information and !each.fights_fire)),
					length(pedestrian where ((each.goes_to_shelter or each.takes_cover_at_home) and each.seeks_information and !each.fights_fire)),
					length(pedestrian where (each.prepares_property and each.fights_fire and each.knows_how_to_fight_fire)),
					length(pedestrian where (each.fights_fire and !each.knows_how_to_fight_fire))
				]
				color:[#blue,#aqua,#green,#red,#orange] line_visible:true;				
			}
		}
	}
}
 

experiment fire_exp type:gui {
	parameter "Initial number of people" var: nb_people min: 0 category:"Initial values";
	
	// Fire
	parameter "Fire probability to grow" var: fire_proba_grow min:0.0 max:1.0 category: "Fire";
	parameter "Fire probability to de-grow" var: fire_proba_ungrow min:0.0 max:1.0 category: "Fire";
	parameter "Fire probability to propagate" var: fire_proba_grow min:0.0 max:1.0 category: "Fire";
	parameter "Fire initial intensity" var: fire_initial_intensity min:0 max:20 category: "Fire";
	parameter "Fire maximum intensity" var: fire_max_intensity min:0 max:20 category: "Fire";
	parameter "Fire damage factor (to buildings)" var: fire_damage_factor init:3 min: 1 max: 10 category: "Fire";	
	parameter "Fire injury factor (to people)" var: fire_injury_factor init:1 min: 1 max: 10 category: "Fire";	
	parameter "Initial number of fires" var:fire_init_number init:10 min:0 max:100 category: "Fire";
	parameter "Max number of fires" var:fire_max_number init:50 min:10 max:100 category: "Fire";
	
	// People
	parameter "People furthest radius of awareness" var:people_further_awareness min: 1 init: 15 category: "People";
	parameter "Probability to detect fire in radius of awareness" var:proba_detection init:1.0 category: "People";
	parameter "People furthest radius to get aware of fire" var:people_further_aversion min:1 init: 10 category: "People";
	parameter "People max radius to impact fire" var:people_defense_radius min:1 init: 4 category: "People";
	parameter "People preparation factor (max preparation action)" var:people_preparation_factor min:1 init: 10 category:"People";
	parameter  "People fighting factor (max defense action)" var:people_fighting_factor min:1 init: 15 category:"People";
	parameter "People motivation update rate" var: motivation_update_rate min:0.0 max:1.0 init:0.2 category: "People";
	parameter "People confidence update rate" var: ability_update_rate min:0.0 max:1.0 init:0.2 category: "People";
	
	// Buildings
	parameter "Building maximum resistance level" var: building_max_resistance init: 300 min:0 max:300 category: "Building";
	parameter "Building resistance to be fire ready" var:building_fire_ready min:0 max:300 init:200 category: "Building";
	parameter "Building protection factor (against fire injuries)" var:building_protection_factor init:0.01 min: 0.0 max: 0.5 category: "Building";
	parameter "Building minimum protection" var:building_min_protection init:2 min:1 max:5;
	
	
	output {
		display fire_display type: opengl {
	        grid world_cell lines: #black;
	        species shelter aspect: basic;	        
	        species building aspect: basic;
	        species pedestrian aspect: basic;
	        species fire aspect: basic;
	    }
	}
}


experiment fire_stat type:gui {
	parameter "Initial number of people" var: nb_people min: 0 category:"Initial values";
	
	// Fire
	parameter "Fire probability to grow" var: fire_proba_grow min:0.0 max:1.0 category: "Fire";
	parameter "Fire probability to de-grow" var: fire_proba_ungrow min:0.0 max:1.0 category: "Fire";
	parameter "Fire probability to propagate" var: fire_proba_grow min:0.0 max:1.0 category: "Fire";
	parameter "Fire initial intensity" var: fire_initial_intensity min:0 max:20 category: "Fire";
	parameter "Fire maximum intensity" var: fire_max_intensity min:0 max:20 category: "Fire";
	parameter "Fire damage factor (to buildings)" var: fire_damage_factor init:3 min: 1 max: 10 category: "Fire";	
	parameter "Fire injury factor (to people)" var: fire_injury_factor init:1 min: 1 max: 10 category: "Fire";	
	parameter "Initial number of fires" var:fire_init_number init:10 min:0 max:100 category: "Fire";
	parameter "Max number of fires" var:fire_max_number init:50 min:10 max:100 category: "Fire";
	
	// People
	parameter "People furthest radius of awareness" var:people_further_awareness min: 1 init: 15 category: "People";
	parameter "Probability to detect fire in radius of awareness" var:proba_detection init:1.0 category: "People";
	parameter "People furthest radius to get aware of fire" var:people_further_aversion min:1 init: 10 category: "People";
	parameter "People max radius to impact fire" var:people_defense_radius min:1 init: 4 category: "People";
	parameter "People preparation factor (max preparation action)" var:people_preparation_factor min:1 init: 10 category:"People";
	parameter  "People fighting factor (max defense action)" var:people_fighting_factor min:1 init: 15 category:"People";
	parameter "People motivation update rate" var: motivation_update_rate min:0.0 max:1.0 init:0.2 category: "People";
	parameter "People confidence update rate" var: ability_update_rate min:0.0 max:1.0 init:0.2 category: "People";
	
	// Buildings
	parameter "Building maximum resistance level" var: building_max_resistance init: 300 min:0 max:300 category: "Building";
	parameter "Building resistance to be fire ready" var:building_fire_ready min:0 max:300 init:200 category: "Building";
	parameter "Building protection factor (against fire injuries)" var:building_protection_factor init:0.01 min: 0.0 max: 0.5 category: "Building";
	parameter "Building minimum protection" var:building_min_protection init:2 min:1 max:5;
	
	
	output {
		display fire_stat type:opengl {
	        grid world_cell lines: #black;
	        species shelter aspect: basic;	        
	        species building aspect: basic;
	        species pedestrian aspect: basic;
	        species fire aspect: basic;
	    }
	    
		// economical graph
		display DamageAndLosses {
			chart "Damages and injuries" type:series {
				datalist ["buildings destroyed", "total damage", "total injuries", "deaths"]
				value: [
					length(building where (each.resistance<=0)),
					0.01*totalDamage,
					0.01*totalInjury,
					length(pedestrian where (each.is_dead))
				]
				color:[#green,#blue,#purple,#black]
				style:line;
			}
		}
		// fires: total number, total intensity, 10*total nb ext, 10*avg nb fires arnd defenders, total fightingactions
		display Fires {
			chart "Fires indicators" type:series {
				datalist ["number of fires", "total intensity"]
				value: [
					length(fire),
					sum(fire collect each.intensity)
				]
				color: [#red,#aqua]
				style: line;
			}
		}
		
		display LastPlan {
			chart "Last plan used before dying" type:pie {
				datalist ["Unaware","Does nothing","Covered at home","Goes to shelter","Seeks information","Prepare property","Fights fire"]
				value:[
					length(pedestrian where (each.is_dead and each.last_plan=0 and !each.aware)),
					length(pedestrian where (each.is_dead and each.last_plan=0 and each.aware)),
					length(pedestrian where (each.is_dead and each.last_plan=1)),
					length(pedestrian where (each.is_dead and each.last_plan=2)),
					length(pedestrian where (each.is_dead and each.last_plan=3)),
					length(pedestrian where (each.is_dead and each.last_plan=4)),
					length(pedestrian where (each.is_dead and each.last_plan=5))
				]
				color:[#blue,#steelblue,#silver,#aqua,#green,#orange,#red] line_visible:true;				
			}
		}
		
		display Profils {
			chart "Pedestrian profils" type:pie {
				datalist ["Unaware reactors","Threat avoiders","Threat monitors","Can-do defenders","Considered defenders"]
				value:[
					length(pedestrian where (each.does_nothing and !each.goes_to_shelter and !each.takes_cover_at_home and !each.seeks_information and !each.prepares_property and !each.fights_fire and each.has_belief(each.belief_danger))),
					length(pedestrian where (each.goes_to_shelter and !each.takes_cover_at_home and !each.seeks_information and !each.fights_fire)),
					length(pedestrian where ((each.goes_to_shelter or each.takes_cover_at_home) and each.seeks_information and !each.fights_fire)),
					length(pedestrian where (each.prepares_property and each.fights_fire and each.knows_how_to_fight_fire)),
					length(pedestrian where (each.fights_fire and !each.knows_how_to_fight_fire))
				]
				color:[#blue,#aqua,#green,#red,#orange] line_visible:true;				
			}
		}
		
		// TODO: graphs for each of the factors that contribute to will to stay / will to leave
		// pour evaluer leur poids respectif
		// puis appliquer un biais sur ces facteurs avant de les ajouter a la motivation globale
	}
}
