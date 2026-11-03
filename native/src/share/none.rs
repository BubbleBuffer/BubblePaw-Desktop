//! The phone build (no `local-host`): there is no host on this device to
//! share, so every call says so. The same names as `local.rs`.

use crate::api::host::BubblePawHost;
use crate::api::remote::*;
use crate::frb_generated::StreamSink;

fn unsupported() -> ShareError {
    ShareError::new(
        ShareErrorKind::Other,
        "this device has no host of its own to share",
    )
}

pub(crate) fn share_settings(
    _data_dir: String,
    _workspace_dir: String,
) -> Result<ShareSettings, ShareError> {
    Err(unsupported())
}

pub(crate) struct Share;
pub(crate) struct Offer;
pub(crate) struct Request;

impl Share {
    pub(crate) fn new(
        _host: &BubblePawHost,
        _data_dir: String,
        _workspace_dir: String,
        _device_name: String,
    ) -> Result<Share, ShareError> {
        Err(unsupported())
    }

    pub(crate) async fn start(&self) -> Result<ShareState, ShareError> {
        Err(unsupported())
    }

    pub(crate) async fn stop(&self) -> Result<(), ShareError> {
        Err(unsupported())
    }

    pub(crate) async fn state(&self) -> ShareState {
        ShareState {
            status: ShareStatus::Off,
            mode: ShareMode::Relay,
            address: None,
            host_id: None,
            last_error: None,
            devices: 0,
        }
    }

    pub(crate) async fn watch(&self, _sink: StreamSink<ShareState>) -> Result<(), ShareError> {
        Err(unsupported())
    }

    pub(crate) async fn pair(&self, _profile: String, _egress: bool) -> Result<Offer, ShareError> {
        Err(unsupported())
    }

    pub(crate) async fn devices(&self) -> Result<Vec<DeviceEntry>, ShareError> {
        Err(unsupported())
    }

    pub(crate) async fn revoke(&self, _id: String) -> Result<bool, ShareError> {
        Err(unsupported())
    }

    pub(crate) fn key_info(&self) -> Result<KeyInfo, ShareError> {
        Err(unsupported())
    }

    pub(crate) async fn export_key(
        &self,
        _dest: String,
        _passphrase: String,
    ) -> Result<(), ShareError> {
        Err(unsupported())
    }

    pub(crate) async fn import_key(
        &self,
        _src: String,
        _passphrase: String,
    ) -> Result<KeyChange, ShareError> {
        Err(unsupported())
    }

    pub(crate) async fn regenerate_key(&self) -> Result<KeyChange, ShareError> {
        Err(unsupported())
    }

    pub(crate) async fn cloudflare_status(&self) -> Result<CloudflareStatus, ShareError> {
        Err(unsupported())
    }

    pub(crate) async fn store_cloudflare_token(&self, _token: String) -> Result<(), ShareError> {
        Err(unsupported())
    }

    pub(crate) async fn forget_cloudflare_token(&self) -> Result<(), ShareError> {
        Err(unsupported())
    }

    pub(crate) async fn login_start(&self) -> Result<LoginPrompt, ShareError> {
        Err(unsupported())
    }

    pub(crate) async fn login_wait(&self, _timeout_secs: u32) -> Result<bool, ShareError> {
        Err(unsupported())
    }

    pub(crate) async fn login_cancel(&self) {}

    pub(crate) async fn cloudflared_info(&self) -> Result<CloudflaredStatus, ShareError> {
        Err(unsupported())
    }

    pub(crate) async fn install_cloudflared(&self) -> Result<CloudflaredStatus, ShareError> {
        Err(unsupported())
    }

    pub(crate) async fn update_cloudflared(&self) -> Result<CloudflaredStatus, ShareError> {
        Err(unsupported())
    }

    pub(crate) fn check_hostname(&self, _hostname: String) -> Result<(), ShareError> {
        Err(unsupported())
    }

    pub(crate) fn serve_status(&self) -> Result<OtherShare, ShareError> {
        Err(unsupported())
    }
}

impl Offer {
    pub(crate) fn code(&self) -> String {
        String::new()
    }

    pub(crate) fn qr_payload(&self) -> String {
        String::new()
    }

    pub(crate) fn address(&self) -> String {
        String::new()
    }

    pub(crate) fn expires_in_secs(&self) -> u32 {
        0
    }

    pub(crate) async fn next_request(&self) -> Option<Request> {
        None
    }

    pub(crate) fn cancel(&self) {}
}

impl Request {
    pub(crate) fn comparison(&self) -> String {
        String::new()
    }

    pub(crate) fn device_name(&self) -> String {
        String::new()
    }

    pub(crate) fn device_id(&self) -> String {
        String::new()
    }

    pub(crate) async fn approve(&self, _name: String) -> Result<DeviceEntry, ShareError> {
        Err(unsupported())
    }

    pub(crate) async fn decline(&self) -> Result<(), ShareError> {
        Err(unsupported())
    }
}
