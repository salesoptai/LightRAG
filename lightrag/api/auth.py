from datetime import datetime, timedelta
import json
import os

import jwt
from dotenv import load_dotenv
from fastapi import HTTPException, status
from pydantic import BaseModel
from lightrag.utils import logger

from .config import global_args

# use the .env that is inside the current folder
# allows to use different .env file for each lightrag instance
# the OS environment variables take precedence over the .env file
load_dotenv(dotenv_path=".env", override=False)


class TokenPayload(BaseModel):
    sub: str  # Username
    exp: datetime  # Expiration time
    role: str = "user"  # User role, default is regular user
    metadata: dict = {}  # Additional metadata


class AuthHandler:
    def __init__(self):
        self.secret = global_args.token_secret
        self.algorithm = global_args.jwt_algorithm
        self.expire_hours = global_args.token_expire_hours
        self.guest_expire_hours = global_args.guest_token_expire_hours
        self.accounts = {}
        self.api_keys = {}
        self.user_map = {}
        
        # Load accounts from environment variable (legacy/simple mode)
        auth_accounts = global_args.auth_accounts
        if auth_accounts:
            for account in auth_accounts.split(","):
                username, password = account.split(":", 1)
                self.accounts[username] = password
                self.user_map[username] = {"username": username, "workspace": "default"}
        
        # Load accounts from users.json (multi-tenant mode)
        self.load_users()

    def load_users(self):
        # In Cloud Run, secrets are often mounted as files.
        # We support an explicit path override to avoid mounting secrets over /app
        # (which can hide the application code and break imports).
        users_path = os.getenv("USERS_JSON_PATH", "users.json")

        if os.path.exists(users_path):
            try:
                with open(users_path, "r") as f:
                    data = json.load(f)
                    for user in data.get("users", []):
                        username = user.get("username")
                        password = user.get("password")
                        api_key = user.get("api_key")
                        
                        if username:
                            self.user_map[username] = user
                            if password:
                                self.accounts[username] = password
                            if api_key:
                                self.api_keys[api_key] = user
                logger.info(
                    f"Loaded {len(self.user_map)} users from {users_path}"
                )
            except Exception as e:
                logger.error(f"Error loading users file {users_path}: {e}")

    def validate_api_key(self, api_key: str) -> dict:
        """
        Validate API Key
        
        Args:
            api_key: The API Key to validate
            
        Returns:
            dict: User info if valid, None otherwise
        """
        if api_key in self.api_keys:
            user = self.api_keys[api_key]
            return {
                "username": user["username"],
                "role": user.get("role", "user"),
                "workspace": user.get("workspace", "default"),
                "metadata": {"auth_mode": "api_key"}
            }
        return None

    def get_user_workspace(self, username: str) -> str:
        """Get workspace for a username"""
        if username in self.user_map:
            return self.user_map[username].get("workspace", "default")
        return "default"

    def create_token(
        self,
        username: str,
        role: str = "user",
        custom_expire_hours: int = None,
        metadata: dict = None,
    ) -> str:
        """
        Create JWT token

        Args:
            username: Username
            role: User role, default is "user", guest is "guest"
            custom_expire_hours: Custom expiration time (hours), if None use default value
            metadata: Additional metadata

        Returns:
            str: Encoded JWT token
        """
        # Choose default expiration time based on role
        if custom_expire_hours is None:
            if role == "guest":
                expire_hours = self.guest_expire_hours
            else:
                expire_hours = self.expire_hours
        else:
            expire_hours = custom_expire_hours

        expire = datetime.utcnow() + timedelta(hours=expire_hours)

        # Create payload
        payload = TokenPayload(
            sub=username, exp=expire, role=role, metadata=metadata or {}
        )

        return jwt.encode(payload.dict(), self.secret, algorithm=self.algorithm)

    def validate_token(self, token: str) -> dict:
        """
        Validate JWT token

        Args:
            token: JWT token

        Returns:
            dict: Dictionary containing user information

        Raises:
            HTTPException: If token is invalid or expired
        """
        try:
            payload = jwt.decode(token, self.secret, algorithms=[self.algorithm])
            expire_timestamp = payload["exp"]
            expire_time = datetime.utcfromtimestamp(expire_timestamp)

            if datetime.utcnow() > expire_time:
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED, detail="Token expired"
                )

            # Return complete payload instead of just username
            username = payload["sub"]
            workspace = self.get_user_workspace(username)
            
            # Allow metadata to override workspace if explicitly set (though usually comes from user config)
            metadata = payload.get("metadata", {})
            if "workspace" not in metadata:
                metadata["workspace"] = workspace

            return {
                "username": username,
                "role": payload.get("role", "user"),
                "metadata": metadata,
                "exp": expire_time,
                "workspace": workspace, # Explicitly return workspace
            }
        except jwt.PyJWTError:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token"
            )


auth_handler = AuthHandler()
