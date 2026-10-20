/* ============================================================
   香港选美大赛投票页交互逻辑
   说明：
   1. 纯原生 JavaScript，无需构建工具，由 Rails 直接托管 public 目录；
   2. Token 保存在 localStorage，请求统一走 /api/v1；
   3. 所有接口返回 { data, message } 或 { error }，这里统一解析。
   ============================================================ */

(function () {
  "use strict";

  var API_BASE = "/api/v1";
  var TOKEN_KEY = "hk_beauty_token";
  var USER_KEY = "hk_beauty_user";
  // 每页 4 位候选人：桌面端正好一行排满，避免出现第二行导致页面纵向滚动
  var PER_PAGE = 4;

  // 页面状态集中管理，避免散落的全局变量
  var state = {
    token: localStorage.getItem(TOKEN_KEY) || "",
    user: readStoredUser(),
    page: 1,
    perPage: PER_PAGE,
    candidates: [],
    meta: null,
    activeCandidate: null,
    countdownTimer: null,
    voting: false
  };

  /* ------------------------------ 工具函数 ------------------------------ */

  function $(id) {
    return document.getElementById(id);
  }

  function readStoredUser() {
    try {
      return JSON.parse(localStorage.getItem(USER_KEY) || "null");
    } catch (error) {
      return null;
    }
  }

  // 统一转义，防止候选人资料中的特殊字符破坏 HTML 结构
  function escapeHtml(value) {
    return String(value == null ? "" : value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;");
  }

  function escapeAttr(value) {
    return escapeHtml(value).replace(/`/g, "&#96;");
  }

  // 头像兜底：取名字首字符，照片加载失败时展示
  function initialOf(name) {
    var chars = Array.from(String(name || "?"));
    return chars.length ? chars[0] : "?";
  }

  // 只允许 http(s) 或站内路径作为图片地址，避免异常协议
  function safePhotoUrl(url) {
    var value = String(url || "").trim();
    if (/^https?:\/\//i.test(value) || value.indexOf("/") === 0) {
      return value;
    }
    return "";
  }

  var toastTimer = null;
  function toast(message, type) {
    var el = $("toast");
    el.textContent = message;
    el.className = "toast is-visible" + (type ? " is-" + type : "");

    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () {
      el.className = "toast";
    }, 3200);
  }

  /* ------------------------------ 接口请求 ------------------------------ */

  /**
   * 统一请求封装
   * @param {string} path 以 / 开头的接口路径（不含 /api/v1）
   * @param {object} options method / body / auth
   */
  async function request(path, options) {
    options = options || {};
    var method = options.method || "GET";
    var auth = options.auth !== false;

    var headers = { Accept: "application/json" };
    if (options.body) {
      headers["Content-Type"] = "application/json";
    }
    if (auth && state.token) {
      headers.Authorization = "Bearer " + state.token;
    }

    var response;
    try {
      response = await fetch(API_BASE + path, {
        method: method,
        headers: headers,
        body: options.body ? JSON.stringify(options.body) : undefined
      });
    } catch (error) {
      throw new Error("无法连接服务器，请检查网络后重试");
    }

    var payload = null;
    try {
      payload = await response.json();
    } catch (error) {
      payload = null;
    }

    if (!response.ok) {
      // 携带 Token 却被判定失效：清理本地登录态并回到登录页
      if (response.status === 401 && auth && state.token) {
        clearSession();
        showAuthView();
      }

      var requestError = new Error(
        (payload && payload.error) || "请求失败（" + response.status + "）"
      );
      requestError.status = response.status;
      throw requestError;
    }

    return payload || {};
  }

  /* ------------------------------ 登录态 ------------------------------ */

  function saveSession(token, user) {
    state.token = token || "";
    state.user = user || null;

    if (state.token) {
      localStorage.setItem(TOKEN_KEY, state.token);
    } else {
      localStorage.removeItem(TOKEN_KEY);
    }

    if (state.user) {
      localStorage.setItem(USER_KEY, JSON.stringify(state.user));
    } else {
      localStorage.removeItem(USER_KEY);
    }

    updateHeader();
  }

  function clearSession() {
    state.token = "";
    state.user = null;
    state.candidates = [];
    state.meta = null;
    state.activeCandidate = null;
    localStorage.removeItem(TOKEN_KEY);
    localStorage.removeItem(USER_KEY);
    updateHeader();
  }

  function updateHeader() {
    var badge = $("user-badge");
    var logoutBtn = $("logout-btn");

    if (state.user) {
      badge.textContent = state.user.username || state.user.phone_number || "已登录";
      badge.classList.remove("hidden");
      logoutBtn.classList.remove("hidden");
    } else {
      badge.textContent = "";
      badge.classList.add("hidden");
      logoutBtn.classList.add("hidden");
    }
  }

  /* ------------------------------ 视图切换 ------------------------------ */

  function showAuthView() {
    // 登出或登录失效后统一回到登录标签，并清空密码、验证码等一次性敏感输入
    switchTab("login");
    resetAuthSensitiveFields();

    $("auth-view").classList.remove("hidden");
    $("list-view").classList.add("hidden");
    closeModal();
  }

  // 只清理敏感与一次性字段，保留手机号/用户名方便用户再次登录
  function resetAuthSensitiveFields() {
    $("login-password").value = "";
    $("reg-password").value = "";
    $("reg-password-confirm").value = "";
    $("reg-code").value = "";
    $("code-hint").textContent = "";
  }

  function showListView() {
    $("auth-view").classList.add("hidden");
    $("list-view").classList.remove("hidden");
  }

  function switchTab(tab) {
    var loginTab = document.querySelector('[data-tab="login"]');
    var registerTab = document.querySelector('[data-tab="register"]');
    var loginForm = $("login-form");
    var registerForm = $("register-form");

    var isLogin = tab === "login";
    loginTab.classList.toggle("is-active", isLogin);
    registerTab.classList.toggle("is-active", !isLogin);
    loginTab.setAttribute("aria-selected", String(isLogin));
    registerTab.setAttribute("aria-selected", String(!isLogin));
    loginForm.classList.toggle("hidden", !isLogin);
    registerForm.classList.toggle("hidden", isLogin);
  }

  /* ------------------------------ 登录 ------------------------------ */

  async function handleLogin(event) {
    event.preventDefault();

    var account = $("login-account").value.trim();
    var password = $("login-password").value;

    if (!account) {
      toast("请输入手机号或用户名", "error");
      return;
    }
    if (!password) {
      toast("请输入密码", "error");
      return;
    }

    // 手机号走 phone_number 字段，其余按用户名处理
    var body = { password: password };
    if (/^1[3-9]\d{9}$/.test(account)) {
      body.phone_number = account;
    } else {
      body.username = account;
    }

    var submitBtn = event.target.querySelector('button[type="submit"]');
    submitBtn.disabled = true;
    submitBtn.textContent = "登录中…";

    try {
      var result = await request("/sessions", { method: "POST", body: body, auth: false });
      saveSession(result.token, result.user);
      enterApp();
      toast("登录成功，欢迎回来", "success");
    } catch (error) {
      toast(error.message, "error");
    } finally {
      submitBtn.disabled = false;
      submitBtn.textContent = "登录";
    }
  }

  /* ------------------------------ 注册 ------------------------------ */

  function startCountdown(seconds) {
    var btn = $("send-code-btn");
    var remaining = seconds;

    clearInterval(state.countdownTimer);
    btn.disabled = true;
    btn.textContent = remaining + " 秒后重发";

    state.countdownTimer = setInterval(function () {
      remaining -= 1;
      if (remaining <= 0) {
        clearInterval(state.countdownTimer);
        btn.disabled = false;
        btn.textContent = "重新获取";
        return;
      }
      btn.textContent = remaining + " 秒后重发";
    }, 1000);
  }

  async function handleSendCode() {
    var phone = $("reg-phone").value.trim();
    var hint = $("code-hint");

    if (!/^1[3-9]\d{9}$/.test(phone)) {
      toast("请输入正确的 11 位手机号", "error");
      return;
    }

    var btn = $("send-code-btn");
    btn.disabled = true;
    btn.textContent = "发送中…";

    try {
      var result = await request("/verification_codes", {
        method: "POST",
        body: { phone_number: phone },
        auth: false
      });

      startCountdown(60);

      // 演示环境后端会返回 debug_code，直接展示，省去查日志的步骤
      if (result.data && result.data.debug_code) {
        hint.textContent = "演示验证码：" + result.data.debug_code;
        toast("验证码已发送，演示码已显示在输入框下方", "success");
      } else {
        hint.textContent = "验证码已发送，5 分钟内有效";
        toast("验证码已发送，请注意查收短信", "success");
      }
    } catch (error) {
      btn.disabled = false;
      btn.textContent = "获取验证码";
      toast(error.message, "error");
    }
  }

  async function handleRegister(event) {
    event.preventDefault();

    var username = $("reg-username").value.trim();
    var phone = $("reg-phone").value.trim();
    var code = $("reg-code").value.trim();
    var password = $("reg-password").value;
    var confirm = $("reg-password-confirm").value;

    if (username.length < 3 || username.length > 20) {
      toast("用户名长度需为 3-20 位", "error");
      return;
    }
    if (!/^1[3-9]\d{9}$/.test(phone)) {
      toast("请输入正确的 11 位手机号", "error");
      return;
    }
    if (!/^\d{6}$/.test(code)) {
      toast("请输入 6 位数字验证码", "error");
      return;
    }
    if (password.length < 6) {
      toast("密码长度不能少于 6 位", "error");
      return;
    }
    if (password !== confirm) {
      toast("两次输入的密码不一致", "error");
      return;
    }

    var submitBtn = event.target.querySelector('button[type="submit"]');
    submitBtn.disabled = true;
    submitBtn.textContent = "注册中…";

    try {
      await request("/users", {
        method: "POST",
        auth: false,
        body: {
          username: username,
          phone_number: phone,
          password: password,
          password_confirmation: confirm,
          verification_code: code
        }
      });
    } catch (error) {
      // 这一层失败才是真正的注册失败：账号未创建，验证码仍可继续使用
      toast(error.message, "error");
      submitBtn.disabled = false;
      submitBtn.textContent = "注册并登录";
      return;
    }

    // 走到这里说明账号已经创建成功、验证码也已被消费，
    // 后面的自动登录失败不能再提示"注册失败"，
    // 否则用户重新注册只会得到"用户名已被占用"。
    try {
      // 注册成功后直接登录，减少一次手动操作
      var loginResult = await request("/sessions", {
        method: "POST",
        auth: false,
        body: { phone_number: phone, password: password }
      });

      saveSession(loginResult.token, loginResult.user);
      enterApp();
      toast("注册成功，已自动登录", "success");
    } catch (error) {
      // 自动登录失败（例如 Redis 不可用返回 503）时降级为手动登录，
      // 账号本身已经可用，这里只把用户引到登录页并回填账号密码
      switchTab("login");
      $("login-account").value = phone;
      $("login-password").value = password;
      toast("注册成功，请手动登录：" + error.message, "error");
    } finally {
      submitBtn.disabled = false;
      submitBtn.textContent = "注册并登录";
    }
  }

  /* ------------------------------ 候选人列表 ------------------------------ */

  function enterApp() {
    showListView();
    loadCandidates(1);
  }

  async function loadCandidates(page) {
    state.page = page || 1;
    $("list-summary").textContent = "正在加载…";

    try {
      var result = await request(
        "/candidates?page=" + state.page + "&per_page=" + state.perPage
      );

      state.candidates = result.data || [];
      state.meta = result.meta || null;

      renderCandidates();
      renderPagination();
    } catch (error) {
      state.candidates = [];
      state.meta = null;
      renderCandidates();
      renderPagination();
      $("list-summary").textContent = "加载失败";
      toast(error.message, "error");
    }
  }

  function renderCandidates() {
    var grid = $("candidate-grid");
    var empty = $("empty-state");
    var meta = state.meta;

    if (!state.candidates.length) {
      grid.innerHTML = "";
      empty.classList.remove("hidden");
      $("list-summary").textContent = meta && meta.total_count === 0
        ? "暂无候选人"
        : "本页没有数据";
      return;
    }

    empty.classList.add("hidden");
    $("list-summary").textContent =
      "共 " + meta.total_count + " 位候选人 · 第 " + meta.current_page + " / " + meta.total_pages + " 页";

    grid.innerHTML = state.candidates
      .map(function (candidate) {
        var photo = safePhotoUrl(candidate.photo_url);
        var photoHtml = photo
          ? '<img src="' + escapeAttr(photo) + '" alt="' + escapeAttr(candidate.name) + '" loading="lazy" onerror="this.remove()" />'
          : "";
        var voted = candidate.has_voted;
        var actionHtml = voted
          ? '<span class="status is-voted">已投票</span>'
          : '<button class="btn btn-primary btn-vote" type="button" data-vote="' + candidate.id + '">投票</button>';

        return (
          '<article class="candidate-card" data-detail="' + candidate.id + '" tabindex="0">' +
            '<div class="candidate-photo">' +
              '<span class="photo-initial">' + escapeHtml(initialOf(candidate.name)) + "</span>" +
              photoHtml +
            "</div>" +
            '<div class="candidate-body">' +
              "<h3>" + escapeHtml(candidate.name) + "</h3>" +
              '<p class="candidate-desc">' + escapeHtml(candidate.description || "暂无简介") + "</p>" +
              '<div class="candidate-actions">' +
                '<span class="status">' + (voted ? "感谢参与" : "等待投票") + "</span>" +
                actionHtml +
              "</div>" +
            "</div>" +
          "</article>"
        );
      })
      .join("");
  }

  function renderPagination() {
    var nav = $("pagination");
    var meta = state.meta;

    if (!meta || meta.total_pages <= 1) {
      nav.innerHTML = "";
      return;
    }

    var html = "";
    html += '<button class="page-btn" type="button" data-page="' + (meta.current_page - 1) + '"' +
      (meta.has_prev ? "" : " disabled") + ">上一页</button>";

    // 只渲染当前页附近的页码，避免页数过多撑破布局
    var start = Math.max(1, meta.current_page - 2);
    var end = Math.min(meta.total_pages, start + 4);
    start = Math.max(1, end - 4);

    for (var page = start; page <= end; page += 1) {
      html += '<button class="page-btn' + (page === meta.current_page ? " is-active" : "") +
        '" type="button" data-page="' + page + '">' + page + "</button>";
    }

    html += '<button class="page-btn" type="button" data-page="' + (meta.current_page + 1) + '"' +
      (meta.has_next ? "" : " disabled") + ">下一页</button>";

    nav.innerHTML = html;
  }

  /* ------------------------------ 投票 ------------------------------ */

  async function voteFor(candidateId) {
    if (state.voting) {
      return;
    }

    state.voting = true;
    setVoteButtonsDisabled(true);

    try {
      await request("/votes", {
        method: "POST",
        body: { candidate_id: candidateId }
      });

      // 本地同步状态，避免为了一个字段重新拉取整页
      state.candidates.forEach(function (candidate) {
        if (candidate.id === candidateId) {
          candidate.has_voted = true;
        }
      });
      if (state.activeCandidate && state.activeCandidate.id === candidateId) {
        state.activeCandidate.has_voted = true;
      }

      renderCandidates();
      refreshModal();
      toast("投票成功，感谢你的参与", "success");
    } catch (error) {
      toast(error.message, "error");
    } finally {
      state.voting = false;
      setVoteButtonsDisabled(false);
      // 投票成功后按钮需要保持禁用，这里统一按最新状态刷新一次弹窗
      refreshModal();
    }
  }

  function setVoteButtonsDisabled(disabled) {
    var buttons = document.querySelectorAll("[data-vote]");
    Array.prototype.forEach.call(buttons, function (button) {
      button.disabled = disabled;
    });

    var modalBtn = $("detail-vote-btn");
    if (modalBtn) {
      modalBtn.disabled = disabled;
    }
  }

  /* ------------------------------ 详情弹窗 ------------------------------ */

  async function openDetail(candidateId) {
    var candidate = findCandidate(candidateId);

    if (!candidate) {
      return;
    }

    state.activeCandidate = candidate;
    fillModal(candidate, safePhotoUrl(candidate.photo_url));
    $("detail-modal").classList.remove("hidden");
    document.body.style.overflow = "hidden";

    // 弹窗打开后再请求一次详情，保证投票状态是最新的
    try {
      var result = await request("/candidates/" + candidateId);
      if (result.data) {
        state.activeCandidate = result.data;
        fillModal(result.data, safePhotoUrl(result.data.photo_url));
        syncCandidate(result.data);
      }
    } catch (error) {
      toast(error.message, "error");
    }
  }

  function fillModal(candidate, photo) {
    var photoBox = $("detail-photo");
    var photoHtml = photo
      ? '<img src="' + escapeAttr(photo) + '" alt="' + escapeAttr(candidate.name) + '" onerror="this.remove()" />'
      : "";

    photoBox.innerHTML =
      '<span class="photo-initial">' + escapeHtml(initialOf(candidate.name)) + "</span>" + photoHtml;

    $("detail-name").textContent = candidate.name;
    $("detail-desc").textContent = candidate.description || "暂无简介";
    refreshModal();
  }

  function refreshModal() {
    var candidate = state.activeCandidate;
    if (!candidate) {
      return;
    }

    var status = $("detail-status");
    var voteBtn = $("detail-vote-btn");

    if (candidate.has_voted) {
      status.textContent = "已为该候选人投票";
      status.className = "status is-voted";
      voteBtn.textContent = "已投票";
      voteBtn.disabled = true;
    } else {
      status.textContent = "尚未投票";
      status.className = "status";
      voteBtn.textContent = "为她投票";
      voteBtn.disabled = false;
    }
  }

  function closeModal() {
    var modal = $("detail-modal");
    if (!modal) {
      return;
    }
    modal.classList.add("hidden");
    document.body.style.overflow = "";
  }

  function syncCandidate(updated) {
    state.candidates.forEach(function (candidate) {
      if (candidate.id === updated.id) {
        candidate.has_voted = updated.has_voted;
      }
    });
    renderCandidates();
  }

  function findCandidate(candidateId) {
    var id = Number(candidateId);
    for (var i = 0; i < state.candidates.length; i += 1) {
      if (state.candidates[i].id === id) {
        return state.candidates[i];
      }
    }
    return null;
  }

  /* ------------------------------ 事件绑定 ------------------------------ */

  function bindEvents() {
    $("login-form").addEventListener("submit", handleLogin);
    $("register-form").addEventListener("submit", handleRegister);
    $("send-code-btn").addEventListener("click", handleSendCode);

    Array.prototype.forEach.call(document.querySelectorAll("[data-tab]"), function (tab) {
      tab.addEventListener("click", function () {
        switchTab(tab.getAttribute("data-tab"));
      });
    });

    Array.prototype.forEach.call(document.querySelectorAll("[data-goto]"), function (button) {
      button.addEventListener("click", function () {
        switchTab(button.getAttribute("data-goto"));
      });
    });

    $("logout-btn").addEventListener("click", async function () {
      try {
        // 通知服务端撤销当前 Token；即使失败也要清理本地状态
        await request("/sessions/current", { method: "DELETE" });
        toast("已退出登录", "success");
      } catch (error) {
        toast(error.message, "error");
      } finally {
        clearSession();
        showAuthView();
      }
    });

    $("refresh-btn").addEventListener("click", function () {
      loadCandidates(state.page);
    });

    // 卡片与投票按钮使用事件委托，避免重复绑定
    $("candidate-grid").addEventListener("click", function (event) {
      var voteButton = event.target.closest("[data-vote]");
      if (voteButton) {
        event.stopPropagation();
        voteFor(Number(voteButton.getAttribute("data-vote")));
        return;
      }

      var card = event.target.closest("[data-detail]");
      if (card) {
        openDetail(Number(card.getAttribute("data-detail")));
      }
    });

    $("candidate-grid").addEventListener("keydown", function (event) {
      if (event.key !== "Enter" && event.key !== " ") {
        return;
      }
      var card = event.target.closest("[data-detail]");
      if (card) {
        event.preventDefault();
        openDetail(Number(card.getAttribute("data-detail")));
      }
    });

    $("pagination").addEventListener("click", function (event) {
      var button = event.target.closest("[data-page]");
      if (!button || button.disabled) {
        return;
      }
      loadCandidates(Number(button.getAttribute("data-page")));
      window.scrollTo({ top: 0, behavior: "smooth" });
    });

    $("detail-vote-btn").addEventListener("click", function () {
      if (state.activeCandidate) {
        voteFor(state.activeCandidate.id);
      }
    });

    Array.prototype.forEach.call(document.querySelectorAll("[data-close-modal]"), function (el) {
      el.addEventListener("click", closeModal);
    });

    document.addEventListener("keydown", function (event) {
      if (event.key === "Escape") {
        closeModal();
      }
    });
  }

  /* ------------------------------ 初始化 ------------------------------ */

  function init() {
    bindEvents();
    updateHeader();

    // 有本地 Token 时先进入列表，失效会在请求 401 时自动回到登录页
    if (state.token) {
      showListView();
      loadCandidates(1);
    } else {
      showAuthView();
    }
  }

  document.addEventListener("DOMContentLoaded", init);
})();
