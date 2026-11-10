import { useEffect, useLayoutEffect, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import { Ellipsis, Pencil, Trash2 } from 'lucide-react';
import type { AdminUser } from '../api/useUsers';

interface UserActionsMenuProps {
  user: AdminUser;
  isOpen: boolean;
  onToggle: () => void;
  onClose: () => void;
  onEdit: () => void;
  onDelete: () => void;
}

interface MenuPosition {
  top: number;
  left: number;
}

const MENU_WIDTH = 176;
const MENU_HEIGHT = 88;
const VIEWPORT_GUTTER = 8;

export default function UserActionsMenu({
  user,
  isOpen,
  onToggle,
  onClose,
  onEdit,
  onDelete,
}: UserActionsMenuProps) {
  const triggerRef = useRef<HTMLButtonElement>(null);
  const menuRef = useRef<HTMLDivElement>(null);
  const firstItemRef = useRef<HTMLButtonElement>(null);
  const [position, setPosition] = useState<MenuPosition>({ top: 0, left: 0 });
  const menuId = `user-actions-menu-${user.id}`;

  useLayoutEffect(() => {
    if (!isOpen) return;

    function updatePosition() {
      const trigger = triggerRef.current;
      const menu = menuRef.current;
      if (!trigger || !menu) return;

      const triggerRect = trigger.getBoundingClientRect();
      const menuRect = menu.getBoundingClientRect();
      const width = menuRect.width || MENU_WIDTH;
      const height = menuRect.height || MENU_HEIGHT;
      const left = Math.max(
        VIEWPORT_GUTTER,
        Math.min(
          triggerRect.right - width,
          window.innerWidth - width - VIEWPORT_GUTTER,
        ),
      );
      const below = triggerRect.bottom + 4;
      const top = below + height <= window.innerHeight - VIEWPORT_GUTTER
        ? below
        : Math.max(VIEWPORT_GUTTER, triggerRect.top - height - 4);

      setPosition({ top, left });
    }

    updatePosition();
    firstItemRef.current?.focus();
    window.addEventListener('resize', updatePosition);
    window.addEventListener('scroll', updatePosition, true);

    return () => {
      window.removeEventListener('resize', updatePosition);
      window.removeEventListener('scroll', updatePosition, true);
    };
  }, [isOpen]);

  useEffect(() => {
    if (!isOpen) return;

    function handlePointerDown(event: PointerEvent) {
      const target = event.target;
      if (
        target instanceof Node &&
        (triggerRef.current?.contains(target) || menuRef.current?.contains(target))
      ) {
        return;
      }
      onClose();
    }

    function handleKeyDown(event: KeyboardEvent) {
      if (event.key !== 'Escape') return;
      event.preventDefault();
      onClose();
      triggerRef.current?.focus();
    }

    document.addEventListener('pointerdown', handlePointerDown);
    document.addEventListener('keydown', handleKeyDown);
    return () => {
      document.removeEventListener('pointerdown', handlePointerDown);
      document.removeEventListener('keydown', handleKeyDown);
    };
  }, [isOpen, onClose]);

  function chooseAction(action: 'edit' | 'delete') {
    onClose();
    if (action === 'edit') onEdit();
    else onDelete();
  }

  return (
    <>
      <button
        ref={triggerRef}
        type="button"
        className="users-actions-trigger"
        aria-label={`Actions for ${user.name}`}
        aria-haspopup="menu"
        aria-expanded={isOpen}
        aria-controls={isOpen ? menuId : undefined}
        onClick={(event) => {
          event.stopPropagation();
          onToggle();
        }}
      >
        <Ellipsis size={18} aria-hidden="true" />
      </button>
      {isOpen && createPortal(
        <div
          ref={menuRef}
          id={menuId}
          className="users-actions-menu"
          role="menu"
          aria-label={`Actions for ${user.name}`}
          style={{ top: position.top, left: position.left }}
        >
          <button
            ref={firstItemRef}
            type="button"
            className="users-actions-menu-item"
            role="menuitem"
            onClick={() => chooseAction('edit')}
          >
            <Pencil size={15} aria-hidden="true" />
            <span>Edit User</span>
          </button>
          <button
            type="button"
            className="users-actions-menu-item users-actions-menu-item--danger"
            role="menuitem"
            onClick={() => chooseAction('delete')}
          >
            <Trash2 size={15} aria-hidden="true" />
            <span>Delete User</span>
          </button>
        </div>,
        document.body,
      )}
    </>
  );
}
