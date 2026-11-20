"""GREEN-API WhatsApp client for SmartCare OTP messages."""
from __future__ import annotations

import os
from typing import Any

import httpx

from backend.countries import phone_to_chat_id as _phone_to_chat_id


def phone_to_chat_id(phone: str, country_iso: str | None = None) -> str:
    return _phone_to_chat_id(phone, country_iso)


def green_config_from_env_and_db(get_setting) -> dict[str, str]:
    """Resolve instance credentials: DB override wins, then env."""
    api_url = (
        (get_setting('green_api_url') or '').strip()
        or (os.getenv('SMARTCARE_GREEN_API_URL') or '').strip()
        or 'https://api.greenapi.com'
    ).rstrip('/')
    id_instance = (
        (get_setting('green_api_id_instance') or '').strip()
        or (os.getenv('SMARTCARE_GREEN_API_ID_INSTANCE') or '').strip()
    )
    token = (
        (get_setting('green_api_token_instance') or '').strip()
        or (os.getenv('SMARTCARE_GREEN_API_TOKEN_INSTANCE') or '').strip()
    )
    enabled = (
        (get_setting('green_api_enabled') or '').strip()
        or (os.getenv('SMARTCARE_GREEN_API_ENABLED') or '').strip()
        or ('1' if id_instance and token else '0')
    )
    return {
        'api_url': api_url,
        'id_instance': id_instance,
        'token_instance': token,
        'enabled': enabled == '1' and bool(id_instance and token),
    }


def send_whatsapp_text(
    *,
    api_url: str,
    id_instance: str,
    token_instance: str,
    phone: str,
    message: str,
    country_iso: str | None = None,
    timeout: float = 20.0,
) -> dict[str, Any]:
    """POST sendMessage to GREEN-API. Returns API JSON (includes idMessage)."""
    chat_id = phone_to_chat_id(phone, country_iso)
    url = f'{api_url.rstrip("/")}/waInstance{id_instance}/sendMessage/{token_instance}'
    with httpx.Client(timeout=timeout) as client:
        res = client.post(
            url,
            json={'chatId': chat_id, 'message': message, 'linkPreview': False},
            headers={'Content-Type': 'application/json'},
        )
    try:
        payload = res.json()
    except Exception:
        payload = {'raw': (res.text or '')[:400]}
    if res.status_code >= 400:
        detail = (
            payload.get('message')
            or payload.get('error')
            or payload.get('raw')
            or f'HTTP {res.status_code}'
        )
        raise RuntimeError(str(detail))
    return payload if isinstance(payload, dict) else {'result': payload}


def otp_message_ar(code: str, purpose: str) -> str:
    if purpose == 'register':
        title = 'إنشاء حساب SmartCare'
        line = 'أدخل هذا الرمز في صفحة إنشاء الحساب لإكمال التسجيل.'
    elif purpose == 'reset':
        title = 'استعادة كلمة المرور'
        line = 'أدخل هذا الرمز في صفحة «نسيت كلمة المرور» لتعيين كلمة جديدة.'
    else:
        title = 'تحقق SmartCare'
        line = 'أدخل الرمز في الصفحة لإكمال الطلب.'
    return (
        f'*SmartCare حائل*\n'
        f'{title}\n'
        f'رمز التحقق: *{code}*\n'
        f'{line}\n'
        f'صالح لمدة 5 دقائق. لا تشارك الرمز مع أحد.\n'
        f'إذا سألت هنا ورقمك مسجّل، نرد عليك من نفس المحادثة.'
    )


def receive_notification(
    *,
    api_url: str,
    id_instance: str,
    token_instance: str,
    timeout: float = 20.0,
) -> dict | None:
    """Long-poll one incoming GREEN-API notification. None if the queue is empty."""
    url = f'{api_url.rstrip("/")}/waInstance{id_instance}/receiveNotification/{token_instance}'
    # Keep HTTP timeout above receiveTimeout; connection resets are common on long-poll.
    with httpx.Client(timeout=httpx.Timeout(timeout + 15.0, connect=20.0)) as client:
        res = client.get(url, params={'receiveTimeout': int(timeout)})
    if res.status_code == 400 or not (res.text or '').strip() or res.text.strip() == 'null':
        return None
    if res.status_code >= 400:
        raise RuntimeError(f'GREEN receive HTTP {res.status_code}')
    data = res.json()
    return data if isinstance(data, dict) else None


def delete_notification(
    *,
    api_url: str,
    id_instance: str,
    token_instance: str,
    receipt_id: int | str,
) -> None:
    url = (
        f'{api_url.rstrip("/")}/waInstance{id_instance}'
        f'/deleteNotification/{token_instance}/{receipt_id}'
    )
    with httpx.Client(timeout=15) as client:
        client.delete(url)


def send_whatsapp_chat(
    *,
    api_url: str,
    id_instance: str,
    token_instance: str,
    chat_id: str,
    message: str,
    timeout: float = 20.0,
) -> dict[str, Any]:
    """POST sendMessage to an exact chatId (e.g. 9665…@c.us)."""
    url = f'{api_url.rstrip("/")}/waInstance{id_instance}/sendMessage/{token_instance}'
    with httpx.Client(timeout=timeout) as client:
        res = client.post(
            url,
            json={'chatId': chat_id, 'message': message, 'linkPreview': False},
            headers={'Content-Type': 'application/json'},
        )
    try:
        payload = res.json()
    except Exception:
        payload = {'raw': (res.text or '')[:400]}
    if res.status_code >= 400:
        detail = (
            payload.get('message')
            or payload.get('error')
            or payload.get('raw')
            or f'HTTP {res.status_code}'
        )
        raise RuntimeError(str(detail))
    return payload if isinstance(payload, dict) else {'result': payload}


def set_incoming_webhook(
    *,
    api_url: str,
    id_instance: str,
    token_instance: str,
    webhook_url: str,
    timeout: float = 20.0,
) -> dict[str, Any]:
    """Point GREEN-API incoming webhooks at our /api/whatsapp/webhook (keeps other settings)."""
    url = f'{api_url.rstrip("/")}/waInstance{id_instance}/setSettings/{token_instance}'
    body = {
        'webhookUrl': (webhook_url or '').strip(),
        'incomingWebhook': 'yes',
        'outgoingMessageWebhook': 'no',
        'outgoingAPIMessageWebhook': 'no',
        'stateWebhook': 'no',
        'deviceWebhook': 'no',
    }
    with httpx.Client(timeout=timeout) as client:
        res = client.post(url, json=body, headers={'Content-Type': 'application/json'})
    try:
        payload = res.json()
    except Exception:
        payload = {'raw': (res.text or '')[:400]}
    if res.status_code >= 400:
        raise RuntimeError(str(payload.get('message') or payload.get('raw') or res.status_code))
    return payload if isinstance(payload, dict) else {'result': payload}


def incoming_text(notification: dict) -> tuple[str, str] | None:
    """Return (chat_id, text) for a private text message, else None.

    Accepts both receiveNotification envelopes ``{body: {...}}`` and raw webhook POSTs.
    """
    if not isinstance(notification, dict):
        return None
    body = notification.get('body')
    if not isinstance(body, dict):
        body = notification
    if body.get('typeWebhook') != 'incomingMessageReceived':
        return None
    sender = (body.get('senderData') or {}).get('chatId') or ''
    # Prefer classic WhatsApp ids; also accept @s.whatsapp.net if GREEN ever sends it.
    if not (sender.endswith('@c.us') or sender.endswith('@s.whatsapp.net')):
        return None
    if sender.endswith('@s.whatsapp.net'):
        sender = sender.replace('@s.whatsapp.net', '@c.us')
    msg = body.get('messageData') or {}
    kind = msg.get('typeMessage')
    text = ''
    if kind == 'textMessage':
        text = ((msg.get('textMessageData') or {}).get('textMessage') or '')
    elif kind == 'extendedTextMessage':
        text = ((msg.get('extendedTextMessageData') or {}).get('text') or '')
    text = ' '.join(str(text).split())
    if not text:
        return None
    return sender, text[:500]
