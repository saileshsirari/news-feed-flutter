//! The same device, for the browser: exported to JavaScript with
//! wasm-bindgen and called from Dart through JS interop (see the package's
//! lib/src/web/). Single-threaded on purpose: every call is a few
//! milliseconds of crypto, and no threads means no cross-origin isolation.

use wasm_bindgen::prelude::*;

use crate::api::device::{MlsDevice, MlsError};

fn js_error(e: MlsError) -> JsError {
    JsError::new(&e.0)
}

#[wasm_bindgen]
pub struct WebMlsDevice(MlsDevice);

#[wasm_bindgen]
impl WebMlsDevice {
    #[wasm_bindgen(constructor)]
    pub fn new(identity: Vec<u8>) -> Result<WebMlsDevice, JsError> {
        MlsDevice::new(identity).map(WebMlsDevice).map_err(js_error)
    }

    #[wasm_bindgen(js_name = keyPackage)]
    pub fn key_package(&self) -> Result<Vec<u8>, JsError> {
        self.0.key_package().map_err(js_error)
    }

    #[wasm_bindgen(js_name = createGroup)]
    pub fn create_group(&mut self, group_id: Vec<u8>) -> Result<(), JsError> {
        self.0.create_group(group_id).map_err(js_error)
    }

    #[wasm_bindgen(js_name = addMember)]
    pub fn add_member(&mut self, group_id: Vec<u8>, key_package: Vec<u8>) -> Result<WebInvitation, JsError> {
        let invitation = self.0.add_member(group_id, key_package).map_err(js_error)?;
        Ok(WebInvitation { commit: invitation.commit, welcome: invitation.welcome })
    }

    pub fn join(&mut self, welcome: Vec<u8>) -> Result<Vec<u8>, JsError> {
        self.0.join(welcome).map_err(js_error)
    }

    pub fn encrypt(&mut self, group_id: Vec<u8>, plaintext: Vec<u8>) -> Result<Vec<u8>, JsError> {
        self.0.encrypt(group_id, plaintext).map_err(js_error)
    }

    pub fn receive(&mut self, group_id: Vec<u8>, message: Vec<u8>) -> Result<WebReceived, JsError> {
        let received = self.0.receive(group_id, message).map_err(js_error)?;
        Ok(WebReceived { sender: received.sender, plaintext: received.plaintext })
    }

    /// The members' identities, as an array of Uint8Array.
    pub fn members(&mut self, group_id: Vec<u8>) -> Result<js_sys::Array, JsError> {
        let members = self.0.members(group_id).map_err(js_error)?;
        Ok(members.into_iter().map(|m| JsValue::from(js_sys::Uint8Array::from(&m[..]))).collect())
    }
}

#[wasm_bindgen]
pub struct WebInvitation {
    commit: Vec<u8>,
    welcome: Vec<u8>,
}

#[wasm_bindgen]
impl WebInvitation {
    #[wasm_bindgen(getter)]
    pub fn commit(&self) -> Vec<u8> {
        self.commit.clone()
    }

    #[wasm_bindgen(getter)]
    pub fn welcome(&self) -> Vec<u8> {
        self.welcome.clone()
    }
}

#[wasm_bindgen]
pub struct WebReceived {
    sender: Option<Vec<u8>>,
    plaintext: Option<Vec<u8>>,
}

#[wasm_bindgen]
impl WebReceived {
    #[wasm_bindgen(getter)]
    pub fn sender(&self) -> Option<Vec<u8>> {
        self.sender.clone()
    }

    #[wasm_bindgen(getter)]
    pub fn plaintext(&self) -> Option<Vec<u8>> {
        self.plaintext.clone()
    }
}
