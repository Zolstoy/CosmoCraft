use super::body::Body;
use core::f64;
use rstar::{RTree, AABB};
use scilib::coordinate::{cartesian::Cartesian, spherical::Spherical};
use std::f64::consts::PI;

#[derive(Default)]
pub struct Galaxy {
    pub(crate) bodies: RTree<Body>,
}

impl Galaxy {
    pub fn insert_body(&mut self, body: Body) {
        self.bodies.insert(body);
    }

    pub fn borrow_bodies(&self) -> Vec<&Body> {
        self.bodies.iter().collect()
    }

    pub fn borrow_body(&self, id: u32) -> Option<&Body> {
        self.bodies.iter().find(|g| g.id == id)
    }

    pub fn borrow_body_mut(&mut self, id: u32) -> Option<&mut Body> {
        self.bodies.iter_mut().find(|g| g.id == id)
    }

    pub fn bodies_in_spherical_view(tree: &RTree<Body>, center: Cartesian, radius: f64) -> Vec<&Body> {
        let radius_sq = radius * radius;
        let min = [center.x - radius, center.y - radius, center.z - radius];
        let max = [center.x + radius, center.y + radius, center.z + radius];
        tree.locate_in_envelope_intersecting(&AABB::from_corners(min, max))
            .filter(|g| {
                let d_sq =
                    (g.coords.x - center.x).powi(2) + (g.coords.y - center.y).powi(2) + (g.coords.z - center.z).powi(2);
                d_sq <= radius_sq
            })
            .collect()
    }

    pub async fn update(&mut self, mut delta: f64) {
        delta *= 10f64;
        if self.bodies.iter().count() < 2 {
            return;
        }

        let mut old_rtree = self.bodies.clone();
        let mut new_rtree = RTree::<Body>::default();
        let mut bodies: Vec<_> = self.bodies.drain().collect();

        while bodies.len() > 0 {
            let mut body = bodies.pop().unwrap();
            old_rtree.remove(&body);

            let gravity_center = bodies.iter().find(|g| g.id == body.gravity_center);

            if let Some(gravity_center) = gravity_center {
                let local_coordinates_car = body.coords - gravity_center.coords;
                let local_coordinates_sph = Spherical::from_coord(local_coordinates_car);
                let mut new_coordinates_sph = local_coordinates_sph.clone();
                new_coordinates_sph.phi = new_coordinates_sph.phi + body.rotating_speed * delta;

                new_coordinates_sph.phi %= PI;

                let delta_car =
                    Cartesian::from_coord(new_coordinates_sph) - Cartesian::from_coord(local_coordinates_sph);

                if delta_car.x.is_normal() && delta_car.y.is_normal() && delta_car.z.is_normal() {
                    body.coords += delta_car;
                    body.current_rot += body.rotating_speed * delta;
                    let mut ids = vec![body.id];

                    while ids.len() > 0 {
                        let id = ids.pop().unwrap();
                        bodies.iter_mut().for_each(|g| {
                            if g.gravity_center == id {
                                g.coords += delta_car;
                                ids.push(g.id);
                            }
                        });
                    }
                }
            }
            old_rtree.insert(body.clone());
            new_rtree.insert(body);
        }

        self.bodies = new_rtree;
    }
}
