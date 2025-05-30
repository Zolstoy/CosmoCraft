use crate::error::Error;
use crate::protocol::state::Body;
use crate::protocol::{IntoMessage, ShipState};
use crate::spacebuild_log;
use crate::tls::{get_connector, ClientPki};
use crate::{
    protocol::{Action, Login},
    Result,
};
use futures::SinkExt;
use rustls_pki_types::ServerName;
use scilib::coordinate::cartesian::Cartesian;
use std::str::FromStr;
use tokio::io::{AsyncRead, AsyncWrite};
use tokio::net::TcpStream;
use tokio_rustls::client::TlsStream;
use tokio_stream::StreamExt;
use tokio_tungstenite::tungstenite::handshake::client::Request;
use tokio_tungstenite::tungstenite::{client::IntoClientRequest, Message};
use tokio_tungstenite::WebSocketStream;

pub struct Bot<S>
where
    S: AsyncRead + AsyncWrite + Unpin,
{
    stream: WebSocketStream<S>,
}

impl<S: AsyncRead + AsyncWrite + Unpin> Bot<S> {
    async fn next_message(&mut self) -> Result<Message> {
        let message = self
            .stream
            .next()
            .await
            .ok_or_else(Error::WsNoMessage)?
            .map_err(|err| Error::WsCantRead(err))?;
        Ok(message)
    }
    pub async fn terminate(&mut self) -> Result<()> {
        self.stream
            .close(None)
            .await
            .map_err(|err| Error::GracefulCloseError(err))?;
        Ok(())
    }

    pub async fn login(&mut self, nickname: &str) -> Result<u32> {
        self.send_action(Action::Login(Login {
            nickname: nickname.to_string(),
        }))
        .await?;

        let response = self.next_message().await?;
        match response {
            Message::Text(response_str) => {
                let login_state: crate::protocol::state::Auth = serde_json::from_str(&response_str)
                    .map_err(|err| Error::DeserializeAuthenticationResponseError(err, response_str.to_string()))?;

                let uuid = u32::from_str(login_state.message.as_str())
                    .map_err(|_err| Error::BadUuidError(login_state.message))?;

                return Ok(uuid);
            }
            _ => return Err(Error::UnexpectedResponse(format!("{:?}", response))),
        }
    }

    async fn send_action<T: IntoMessage>(&mut self, action: T) -> Result<()> {
        self.stream
            .send(action.to_message()?)
            .await
            .map_err(|err| Error::WsCantSend(err))?;
        Ok(())
    }

    pub async fn move_in_space(&mut self, direction: Cartesian) -> Result<()> {
        self.send_action(Action::ShipState(ShipState {
            throttle_up: true,
            direction: [direction.x, direction.y, direction.z],
        }))
        .await?;
        Ok(())
    }

    pub async fn next_game_state(&mut self) -> Result<crate::protocol::state::Game> {
        let next = self.next_message().await?;

        match next {
            Message::Text(text) => {
                let game_state =
                    serde_json::from_str(&text).map_err(|err| Error::DeserializeError(text.to_string(), err))?;
                Ok(game_state)
            }
            _ => {
                unreachable!()
            }
        }
    }

    pub async fn until_player_state(&mut self) -> Result<crate::protocol::state::Player> {
        loop {
            let game_state = self.next_game_state().await?;

            if let crate::protocol::state::Game::Player(player) = game_state {
                return Ok(player);
            }
        }
    }

    pub async fn until_env_state(&mut self) -> Result<Vec<Body>> {
        loop {
            let game_state = self.next_game_state().await?;

            match game_state {
                crate::protocol::state::Game::Env(bodies) => return Ok(bodies),
                _ => {
                    spacebuild_log!(info, "tests", "Unexpected game info: {:?}", game_state);
                }
            }
        }
    }

    pub async fn until_pong(&mut self) -> Result<f64> {
        loop {
            let game_state = self.next_game_state().await?;

            if let crate::protocol::state::Game::Pong(value) = game_state {
                return Ok(value);
            }
        }
    }

    pub async fn ping(&mut self, id: u32, value: f64) -> Result<()> {
        self.send_action(Action::Ping((id, value))).await
    }
}

fn build_params(hostname: &str, port: u16, secure: bool) -> Result<(String, Request)> {
    let socket_addr = format!("{}:{}", hostname, port);
    let protocol = if secure { "wss" } else { "ws" };
    let url = format!("{}://{}", protocol, socket_addr);
    let request = url
        .clone()
        .into_client_request()
        .map_err(|_err| Error::UrlIntoRequest)?;
    Ok((socket_addr, request))
}

async fn connect_tcp(url: &str) -> Result<TcpStream> {
    let stream = TcpStream::connect(url)
        .await
        .map_err(|err| Error::TcpCouldNotConnect(err))?;
    Ok(stream)
}

async fn connect_websocket<S>(request: Request, stream: S) -> Result<Bot<S>>
where
    S: AsyncRead + AsyncWrite + Unpin,
{
    match tokio_tungstenite::client_async(request, stream).await {
        Ok((stream, _response)) => return Ok(Bot::<S> { stream }),
        Err(err) => {
            return Err(Error::WebSocketUpgrade(err));
        }
    }
}

pub async fn connect_secure(hostname: &str, port: u16, pki: ClientPki<'_>) -> Result<Bot<TlsStream<TcpStream>>> {
    let (socket_addr, request) = build_params(hostname, port, true)?;
    let stream = connect_tcp(socket_addr.as_str()).await?;

    let tls_connector = get_connector(pki)?;
    let stream = tls_connector
        .connect(
            ServerName::try_from("localhost").map_err(|err| Error::TlsHandshakeError(err))?,
            stream,
        )
        .await
        .map_err(|err| Error::CouldNotUpgradeToTls(err))?;

    let stream = connect_websocket(request, stream).await?;
    Ok(stream)
}

pub async fn connect_plain(hostname: &str, port: u16) -> Result<Bot<TcpStream>> {
    let (socket_addr, request) = build_params(hostname, port, true)?;
    let stream = connect_tcp(socket_addr.as_str()).await?;
    let stream = connect_websocket(request, stream).await?;
    Ok(stream)
}
