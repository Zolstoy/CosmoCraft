use std::collections::HashMap;

use scilib::coordinate::cartesian::Cartesian;
use tokio::sync::mpsc::{error::TryRecvError, Receiver, Sender};

use crate::{
    body::Body,
    protocol::{self, Action},
    spacebuild_log,
};

pub struct Player {
    pub(crate) id: u32,
    pub(crate) nickname: String,
    pub(crate) coords: Cartesian,
    pub(crate) direction: Cartesian,
    pub(crate) current_system: u32,
    pub(crate) action_recv: Receiver<Action>,
    pub(crate) state_send: Sender<protocol::state::Game>,
    pub(crate) first_state_sent: bool,
    pub(crate) prev_lag_values: Vec<f64>,
}

impl PartialEq for Player {
    fn eq(&self, other: &Self) -> bool {
        self.nickname == other.nickname
    }
}

impl Player {
    pub(crate) fn new(
        nickname: String,
        state_send: Sender<protocol::state::Game>,
        action_recv: Receiver<Action>,
    ) -> Self {
        Self {
            id: 0,
            nickname,
            coords: Cartesian::default(),
            direction: Cartesian::default(),
            current_system: 0,
            action_recv,
            state_send,
            first_state_sent: false,
            prev_lag_values: Vec::new(),
        }
    }

    pub async fn update(&mut self, delta: f64, env: Vec<&Body>, history: &Vec<HashMap<u32, Body>>) -> bool {
        let mut direction = Cartesian::default();
        let mut throttle_up = false;

        loop {
            match self.action_recv.try_recv() {
                Err(TryRecvError::Empty) => break,
                Err(TryRecvError::Disconnected) => {
                    spacebuild_log!(info, "Player", "Channel disconnected");
                    return false;
                }
                Ok(action) => match action {
                    Action::ShipState(ship_state) => {
                        if ship_state.throttle_up {
                            throttle_up = ship_state.throttle_up;
                            direction = Cartesian::from(
                                ship_state.direction[0],
                                ship_state.direction[1],
                                ship_state.direction[2],
                            );
                            direction /= direction.norm();
                        }
                    }
                    Action::Ping((body_id, body_rot_angle)) => {
                        spacebuild_log!(info, "Player", "Ping: ({body_id}, {body_rot_angle})");
                        let mut prev_phi = 0f64;
                        let mut i = 0;

                        for cache in history.iter().rev() {
                            if !cache.contains_key(&body_id) {
                                break;
                            }
                            let ent = cache.get(&body_id).unwrap();

                            if prev_phi == 0f64 {
                                prev_phi = ent.current_rot;
                            }

                            if body_rot_angle > ent.current_rot {
                                self.prev_lag_values.push(
                                    (i as f64) * 0.1 + ((prev_phi - body_rot_angle) / (prev_phi - ent.current_rot)),
                                );
                                if self.prev_lag_values.len() > 1000 {
                                    self.prev_lag_values.remove(0);
                                }
                                break;
                            }
                            prev_phi = ent.current_rot;
                            i += 1;
                        }

                        let average_lag_value = if !self.prev_lag_values.is_empty() {
                            self.prev_lag_values.iter().sum::<f64>() / self.prev_lag_values.len() as f64
                        } else {
                            0f64
                        };

                        if self
                            .state_send
                            .send(protocol::state::Game::Pong(average_lag_value))
                            .await
                            .is_err()
                        {
                            spacebuild_log!(warn, self.nickname, "Failed to send pong");
                        }
                    }
                    _ => todo!(),
                },
            }
        }

        if direction.norm() > 0f64 {
            self.coords += direction / direction.norm() * 100f64 * delta;
        }

        if throttle_up || !self.first_state_sent {
            spacebuild_log!(trace, "player", "Sending ");
            let result = self
                .state_send
                .send(protocol::state::Game::Player(protocol::state::Player {
                    coords: [self.coords.x, self.coords.y, self.coords.z],
                }))
                .await;

            if result.is_err() {
                spacebuild_log!(warn, self.nickname, "Failed to send player info");
            }
        }

        if !self.first_state_sent {
            self.first_state_sent = true
        }
        let mut bodies: Vec<protocol::state::Body> = Vec::new();

        if env.is_empty() {
            self.state_send.send(protocol::state::Game::Env(vec![])).await.unwrap();
            return true;
        }
        for body in env {
            bodies.push(body.clone().into());

            if bodies.len() == 50 {
                spacebuild_log!(
                    trace,
                    format!("{}:{}", self.id, self.nickname),
                    "Sending {} bodies state data",
                    bodies.len()
                );
                self.state_send
                    .send(protocol::state::Game::Env(bodies.clone()))
                    .await
                    .unwrap();
                bodies.clear();
            }
        }
        if !bodies.is_empty() {
            self.state_send
                .send(protocol::state::Game::Env(bodies.clone()))
                .await
                .unwrap();
        }
        true
    }
}
