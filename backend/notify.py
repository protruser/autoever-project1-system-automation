"""설정 페이지 "Slack Webhook URL" / "알림 트리거"용 최소 알림 발송기.

이메일은 발신용 SMTP 서버 정보가 설정 화면에 없어 보낼 방법이 없으므로 뺐다.
Slack은 입력받은 Webhook URL로 그냥 POST 한 번이면 되므로 여기서 실제로 보낸다.
"""

import json
import urllib.error
import urllib.request


def send_slack(webhook_url, text):
    """Slack Incoming Webhook으로 텍스트 메시지 1건을 보낸다.

    알림은 best-effort다 - Webhook URL이 잘못됐거나 Slack이 응답하지 않아도
    예외를 던지지 않는다. 진단/조치 자체는 알림 발송 성패와 무관하게 항상
    정상적으로 끝나야 하기 때문이다.
    """
    if not webhook_url:
        return
    try:
        body = json.dumps({"text": text}).encode("utf-8")
        req = urllib.request.Request(
            webhook_url,
            data=body,
            headers={"Content-Type": "application/json"},
        )
        urllib.request.urlopen(req, timeout=5)
    except (urllib.error.URLError, OSError, ValueError):
        pass
