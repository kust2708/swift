model worldcell

import "../modelAPIA.gaml"
import "building.gaml"

global
{
	string EMPTY_CELL <- "";
	string BUILDING_CELL <- "building";
	string FIRE_CELL <- "on_fire";
	string HOTSPOT_CELL <- "hot";
	string SHELTER_CELL <- "shelter";
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
	int distance <- -1;						// for safe path
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

